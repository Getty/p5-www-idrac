package FakeiDRAC;

# An in-memory stand-in for the Redfish service of an iDRAC, used as the
# LWP::UserAgent of the code under test.
#
#   my $fake  = FakeiDRAC->new;                                        # the invented controller below
#   my $fake  = FakeiDRAC->from_file('t/fixtures/idrac8/redfish.json'); # a recorded one
#   my $idrac = WWW::iDRAC->new( host => $fake->host, username => 'root', password => 'calvin', ua => $fake );
#
# The documents are a map of path to document. What the fake does with them
# is only what Redfish itself prescribes: the service root is readable
# without a login, everything else wants a session token or Basic
# credentials, a session is created with a POST to the collection the service
# root names, and an action is a POST to its target.
#
# default_docs has the shape of a 13th generation server, with invented
# values. It is not a recording. What a real iDRAC 7 or 8 answers is in
# t/fixtures/, and t/85-fixtures.t runs every capability against those.

use strict;
use warnings;
use parent 'LWP::UserAgent';
use HTTP::Response;
use JSON::MaybeXS;
use MIME::Base64 qw( decode_base64 );
use URI;

my $JSON = JSON::MaybeXS->new( utf8 => 1, canonical => 1 );

sub new {
  my ( $class, %arg ) = @_;
  my $self = $class->SUPER::new;
  %$self = (
    %$self,
    host     => 'idrac.test',
    docs     => $arg{docs} || $class->default_docs,
    username => 'root',
    password => 'calvin',
    tokens   => {},
    requests => [],
    seq      => 0,
    delay    => $arg{delay} // 0,
    pending  => undef
  );
  return $self;
}

sub from_file {
  my ( $class, $file, %arg ) = @_;
  open my $fh, '<:raw', $file or die 'cannot read '.$file.': '.$!;
  my $docs = $JSON->decode( do { local $/; <$fh> } );
  return $class->new( %arg, docs => $docs );
}

sub host     { $_[0]{host} }
sub requests { $_[0]{requests} }
sub sessions { scalar keys %{ $_[0]{tokens} } }

# the document at a path, to change it in a test
sub doc { $_[0]{docs}{ $_[1] } }

sub remove { delete $_[0]{docs}{ $_[1] }; return }

# what a restart of the controller does to the sessions it handed out
sub forget_tokens { $_[0]{tokens} = {}; return }

# the requests that match, as "METHOD path"
sub seen {
  my ( $self, $pattern ) = @_;
  return grep { $_ =~ $pattern } map { $_->method.' '.URI->new( $_->uri )->path_query } @{ $self->{requests} };
}

sub _reply {
  my ( $self, $status, $data, %header ) = @_;
  my $response = HTTP::Response->new( $status, $status < 300 ? 'OK' : 'Error' );
  $response->header(%header) if %header;
  if ( defined $data ) {
    $response->header( 'Content-Type' => 'application/json' );
    $response->content( $JSON->encode($data) );
  }
  return $response;
}

sub _error {
  my ( $self, $status, $id, $message, $resolution ) = @_;
  return $self->_reply( $status, {
    error => {
      code                    => 'Base.1.0.GeneralError',
      message                 => 'A general error has occurred. See ExtendedInfo for more information.',
      '@Message.ExtendedInfo' => [ { MessageId => $id, Message => $message, Resolution => $resolution, Severity => 'Warning' } ]
    }
  } );
}

sub _key {
  my ( $self, $path ) = @_;
  $path =~ s{/+\z}{} unless $path eq '/';
  return $path;
}

sub _authorized {
  my ( $self, $request ) = @_;
  my $token = $request->header('X-Auth-Token');
  return 1 if defined $token && $self->{tokens}{$token};
  my ( $basic ) = ( $request->header('Authorization') // '' ) =~ /\ABasic (.+)\z/;
  return defined $basic && decode_base64($basic) eq $self->{username}.':'.$self->{password} ? 1 : 0;
}

sub _sessions_path {
  my ( $self ) = @_;
  my $root = $self->{docs}{'/redfish/v1'} || {};
  return $root->{Links} && $root->{Links}{Sessions} ? $root->{Links}{Sessions}{'@odata.id'} : undef;
}

# the action whose target is this path, as ( name, action, document that offers it )
sub _action {
  my ( $self, $path ) = @_;
  for my $doc ( values %{ $self->{docs} } ) {
    next unless ref $doc eq 'HASH' && ref $doc->{Actions} eq 'HASH';
    for my $name ( keys %{ $doc->{Actions} } ) {
      my $action = $doc->{Actions}{$name};
      return ( $name, $action, $doc ) if ref $action eq 'HASH' && ( $action->{target} // '' ) eq $path;
    }
  }
  return;
}

sub request {
  my ( $self, $request ) = @_;
  push @{ $self->{requests} }, $request;
  my $uri    = URI->new( $request->uri );
  my $path   = $self->_key( $uri->path_query );
  my $method = $request->method;
  my $body   = length( $request->content // '' ) ? $JSON->decode( $request->content ) : undef;

  return $self->_reply( 200, $self->{docs}{'/redfish/v1'} ) if $method eq 'GET' && $path eq '/redfish/v1';

  my $sessions = $self->_sessions_path;
  if ( defined $sessions && $method eq 'POST' && $path eq $sessions ) {
    return $self->_error( 401, 'IDRAC.1.6.SYS415', 'Unable to complete the operation because the username or password is not correct.', 'Enter valid credentials and retry the operation.' )
      unless ( $body->{UserName} // '' ) eq $self->{username} && ( $body->{Password} // '' ) eq $self->{password};
    my $id    = ++$self->{seq};
    my $token = 'token-'.$id;
    $self->{tokens}{$token} = $id;
    return $self->_reply( 201, { '@odata.id' => $sessions.'/'.$id, Id => "$id", UserName => $self->{username} },
      'X-Auth-Token' => $token, Location => 'https://'.$self->{host}.$sessions.'/'.$id );
  }

  return $self->_error( 401, 'Base.1.0.AccessDenied', 'The authentication credentials included with this request are missing or invalid.', 'Log in again.' )
    unless $self->_authorized($request);

  if ( defined $sessions && $method eq 'DELETE' && $path =~ m{\A\Q$sessions\E/(\d+)\z} ) {
    my $id = $1;
    delete $self->{tokens}{$_} for grep { $self->{tokens}{$_} == $id } keys %{ $self->{tokens} };
    return $self->_reply(204);
  }

  if ( $method eq 'GET' ) {
    my $doc = $self->{docs}{$path}
      or return $self->_error( 404, 'Base.1.0.ResourceMissingAtURI', 'The resource at the URI '.$path.' was not found.', 'Check the URI and retry.' );
    if ( $self->{pending} && $path eq $self->{pending}{path} && --$self->{pending}{after} < 0 ) {
      $doc->{PowerState} = $self->{pending}{state};
      $self->{pending} = undef;
    }
    return $self->_reply( 200, $doc );
  }

  if ( $method eq 'POST' ) {
    my ( $name, $action, $owner ) = $self->_action($path)
      or return $self->_error( 404, 'Base.1.0.ResourceMissingAtURI', 'The resource at the URI '.$path.' was not found.', 'Check the URI and retry.' );
    if ( $name eq '#ComputerSystem.Reset' || $name eq '#Manager.Reset' ) {
      my $type    = $body->{ResetType} // '';
      my $allowed = $action->{'ResetType@Redfish.AllowableValues'};
      return $self->_error( 400, 'Base.1.0.ActionParameterNotSupported', 'The parameter ResetType for the action is not supported: '.$type, 'Use one of the allowable values.' )
        if $allowed && !grep { $_ eq $type } @$allowed;
      if ( $name eq '#Manager.Reset' ) {
        $self->forget_tokens;
        return $self->_reply(204);
      }
      my $state = $type =~ /\A(?:ForceOff|GracefulShutdown)\z/ ? 'Off' : 'On';
      if ( $self->{delay} ) { $self->{pending} = { path => $self->_key( $owner->{'@odata.id'} ), state => $state, after => $self->{delay} } }
      else                  { $owner->{PowerState} = $state }
      return $self->_reply(204);
    }
    if ( $name eq '#LogService.ClearLog' ) {
      my $entries = $self->{docs}{ $self->_key( $owner->{Entries}{'@odata.id'} ) };
      @$entries{ 'Members', 'Members@odata.count' } = ( [], 0 ) if $entries;
      return $self->_reply(204);
    }
    return $self->_reply(204);
  }

  return $self->_error( 405, 'Base.1.0.GeneralError', 'Method not allowed.', 'Use a supported method.' );
}

sub default_docs {
  my $system  = '/redfish/v1/Systems/System.Embedded.1';
  my $chassis = '/redfish/v1/Chassis/System.Embedded.1';
  my $manager = '/redfish/v1/Managers/iDRAC.Embedded.1';
  my $ref     = sub { { '@odata.id' => $_[0] } };
  my $ok      = { Health => 'OK', State => 'Enabled' };
  return {
    '/redfish/v1' => {
      '@odata.id'    => '/redfish/v1',
      RedfishVersion => '1.0.2',
      Systems        => $ref->('/redfish/v1/Systems'),
      Chassis        => $ref->('/redfish/v1/Chassis'),
      Managers       => $ref->('/redfish/v1/Managers'),
      Links          => { Sessions => $ref->('/redfish/v1/Sessions') }
    },
    '/redfish/v1/Systems'  => { Members => [ $ref->($system) ],  'Members@odata.count' => 1 },
    '/redfish/v1/Chassis'  => { Members => [ $ref->('/redfish/v1/Chassis/Enclosure.Internal.0-1'), $ref->($chassis) ], 'Members@odata.count' => 2 },
    '/redfish/v1/Managers' => { Members => [ $ref->($manager) ], 'Members@odata.count' => 1 },
    $system => {
      '@odata.id'        => $system,
      Manufacturer       => 'Dell Inc.',
      Model              => 'PowerEdge T330',
      SKU                => 'TAG0001',
      SerialNumber       => 'SERIAL0001',
      UUID               => '00000000-0000-0000-0000-000000000001',
      AssetTag           => '',
      HostName           => 'server.example.org',
      BiosVersion        => '2.4.3',
      PowerState         => 'On',
      Status             => $ok,
      ProcessorSummary   => { Count => 1, Model => 'Intel(R) Xeon(R) CPU E3-1230 v5 @ 3.40GHz' },
      MemorySummary      => { TotalSystemMemoryGiB => 32 },
      Processors         => $ref->( $system.'/Processors' ),
      EthernetInterfaces => $ref->( $system.'/EthernetInterfaces' ),
      Links              => { Chassis => [ $ref->($chassis) ], ManagedBy => [ $ref->($manager) ] },
      Actions            => {
        '#ComputerSystem.Reset' => {
          target                              => $system.'/Actions/ComputerSystem.Reset',
          'ResetType@Redfish.AllowableValues' => [qw( On ForceOff GracefulRestart GracefulShutdown PushPowerButton Nmi )]
        }
      }
    },
    $system.'/Processors'              => { Members => [ $ref->( $system.'/Processors/CPU.Socket.1' ) ], 'Members@odata.count' => 1 },
    $system.'/Processors/CPU.Socket.1' => {
      '@odata.id' => $system.'/Processors/CPU.Socket.1',
      Id          => 'CPU.Socket.1',
      Socket      => 'CPU.Socket.1',
      Model       => 'Intel(R) Xeon(R) CPU E3-1230 v5 @ 3.40GHz',
      TotalCores  => 4,
      TotalThreads => 8,
      MaxSpeedMHz => 4000,
      Status      => $ok
    },
    $system.'/EthernetInterfaces' => {
      Members => [ $ref->( $system.'/EthernetInterfaces/NIC.Embedded.1-1-1' ), $ref->( $system.'/EthernetInterfaces/NIC.Embedded.2-1-1' ) ],
      'Members@odata.count' => 2
    },
    $system.'/EthernetInterfaces/NIC.Embedded.1-1-1' => {
      '@odata.id' => $system.'/EthernetInterfaces/NIC.Embedded.1-1-1',
      Id          => 'NIC.Embedded.1-1-1',
      MACAddress  => '00:00:5E:00:53:01',
      SpeedMbps   => 1000,
      LinkStatus  => 'LinkUp',
      Status      => $ok
    },
    $system.'/EthernetInterfaces/NIC.Embedded.2-1-1' => {
      '@odata.id'         => $system.'/EthernetInterfaces/NIC.Embedded.2-1-1',
      Id                  => 'NIC.Embedded.2-1-1',
      PermanentMACAddress => '00:00:5E:00:53:02',
      SpeedMbps           => undef,
      LinkStatus          => 'LinkDown',
      Status              => { Health => undef, State => 'Enabled' }
    },
    '/redfish/v1/Chassis/Enclosure.Internal.0-1' => { '@odata.id' => '/redfish/v1/Chassis/Enclosure.Internal.0-1', Id => 'Enclosure.Internal.0-1' },
    $chassis => {
      '@odata.id' => $chassis,
      Id          => 'System.Embedded.1',
      Thermal     => $ref->( $chassis.'/Thermal' ),
      Power       => $ref->( $chassis.'/Power' )
    },
    $chassis.'/Thermal' => {
      Temperatures => [
        {
          Name                      => 'System Board Inlet Temp',
          ReadingCelsius            => 23,
          UpperThresholdNonCritical => 42,
          UpperThresholdCritical    => 47,
          LowerThresholdNonCritical => 3,
          LowerThresholdCritical    => -7,
          Status                    => $ok
        },
        # a sensor the controller lists without a reading
        { Name => 'CPU2 Temp', ReadingCelsius => undef, Status => { Health => undef, State => 'Absent' } }
      ],
      Fans => [
        { FanName => 'System Board Fan1', Reading => 4800, ReadingUnits => 'RPM', Status => $ok },
        { Name    => 'System Board Fan2', Reading => 0,    ReadingUnits => 'RPM', Status => { Health => 'Critical', State => 'Enabled' } }
      ]
    },
    $chassis.'/Power' => {
      PowerControl => [ {
        PowerConsumedWatts => 87,
        PowerCapacityWatts => 495,
        PowerMetrics       => { AverageConsumedWatts => 84, MinConsumedWatts => 61, MaxConsumedWatts => 143 }
      } ],
      Voltages => [
        { Name => 'PS1 Voltage 1', ReadingVolts => 230, Status => $ok },
        { Name => 'System Board 3.3V PG', ReadingVolts => undef, Status => $ok }
      ],
      PowerSupplies => [ {
        Name                 => 'PS1 Status',
        Model                => 'PWR SPLY,495W,RDNT,DELTA  ',
        SerialNumber         => 'SERIAL0002',
        FirmwareVersion      => '00.1D.7D',
        PowerCapacityWatts   => 495,
        LineInputVoltage     => 230,
        LastPowerOutputWatts => 87,
        Status               => { Health => 'Warning', State => 'Enabled' }
      } ]
    },
    $manager => {
      '@odata.id'        => $manager,
      Id                 => 'iDRAC.Embedded.1',
      Model              => '13G Monolithic',
      FirmwareVersion    => '2.83.83.83',
      DateTime           => '2026-10-04T12:00:00+02:00',
      UUID               => '00000000-0000-0000-0000-000000000002',
      Status             => $ok,
      LogServices        => $ref->( $manager.'/LogServices' ),
      EthernetInterfaces => $ref->( $manager.'/EthernetInterfaces' ),
      Actions            => {
        '#Manager.Reset' => { target => $manager.'/Actions/Manager.Reset', 'ResetType@Redfish.AllowableValues' => ['GracefulRestart'] }
      }
    },
    $manager.'/EthernetInterfaces'               => { Members => [ $ref->( $manager.'/EthernetInterfaces/iDRAC.Embedded.1%23NIC.1' ) ], 'Members@odata.count' => 1 },
    $manager.'/EthernetInterfaces/iDRAC.Embedded.1%23NIC.1' => {
      Id            => 'iDRAC.Embedded.1#NIC.1',
      HostName      => 'idrac-TAG0001',
      FQDN          => 'idrac-TAG0001.example.org',
      MACAddress    => '00:00:5E:00:53:10',
      IPv4Addresses => [ { Address => '192.0.2.10', SubnetMask => '255.255.255.0', Gateway => '192.0.2.1', AddressOrigin => 'Static' } ],
      IPv6Addresses => [ { Address => '2001:db8::10', PrefixLength => 64 }, { Address => '::', PrefixLength => 0 } ],
      NameServers   => [ '192.0.2.53', '0.0.0.0', '::' ]
    },
    $manager.'/LogServices' => { Members => [ $ref->( $manager.'/LogServices/Sel' ), $ref->( $manager.'/LogServices/Lclog' ) ], 'Members@odata.count' => 2 },
    $manager.'/LogServices/Sel' => {
      '@odata.id' => $manager.'/LogServices/Sel',
      Id          => 'Sel',
      Entries     => $ref->( $manager.'/Logs/Sel' ),
      Actions     => { '#LogService.ClearLog' => { target => $manager.'/LogServices/Sel/Actions/LogService.ClearLog' } }
    },
    $manager.'/LogServices/Lclog' => { '@odata.id' => $manager.'/LogServices/Lclog', Id => 'Lclog', Entries => $ref->( $manager.'/Logs/Lclog' ) },
    # the whole entries inside the collection, and not in order
    $manager.'/Logs/Sel' => {
      'Members@odata.count' => 3,
      Members               => [
        { '@odata.id' => $manager.'/Logs/Sel/2', Id => '2', Created => '2026-10-02T08:00:00+02:00', Severity => 'Critical', Message => 'Fan 2 failed.', MessageId => 'FAN0001' },
        { '@odata.id' => $manager.'/Logs/Sel/3', Id => '3', Created => '2026-10-03T09:30:00+02:00', Severity => 'OK', Message => 'Fan 2 was restored.', MessageId => 'FAN0002' },
        { '@odata.id' => $manager.'/Logs/Sel/1', Id => '1', Created => '2026-10-01T07:00:00+02:00', Severity => 'Warning', Message => 'The chassis is open.', MessageId => 'SEC0000' }
      ]
    },
    # only addresses inside the collection, and a second page
    $manager.'/Logs/Lclog' => {
      'Members@odata.count'    => 3,
      Members                  => [ $ref->( $manager.'/Logs/Lclog/3' ), $ref->( $manager.'/Logs/Lclog/2' ) ],
      'Members@odata.nextLink' => $manager.'/Logs/Lclog?$skip=2'
    },
    $manager.'/Logs/Lclog?$skip=2' => { 'Members@odata.count' => 3, Members => [ $ref->( $manager.'/Logs/Lclog/1' ) ] },
    $manager.'/Logs/Lclog/3' => { Id => '3', Created => '2026-10-03T10:00:00+02:00', Severity => 'OK', Message => 'Successfully logged in.', MessageId => 'USR0030' },
    $manager.'/Logs/Lclog/2' => { Id => '2', Created => '2026-10-02T10:00:00+02:00', Severity => 'OK', Message => 'The system was turned on.', MessageId => 'SYS1000' },
    $manager.'/Logs/Lclog/1' => { Id => '1', Created => '2026-10-01T10:00:00+02:00', Severity => 'Informational', Message => 'The Lifecycle log was archived.', MessageId => 'LOG007' }
  };
}

1;
