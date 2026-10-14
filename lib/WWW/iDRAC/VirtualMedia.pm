package WWW::iDRAC::VirtualMedia;

# ABSTRACT: Remote image (virtual media) of an iDRAC 7 or 8, over racadm

use Moo;
use Scalar::Util qw( blessed );
use WWW::iDRAC::Error::Validation;
use WWW::iDRAC::Racadm;
use WWW::iDRAC::Util qw( text );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'virtual_media' }

with 'WWW::iDRAC::Role::Racadm';

=synopsis

    my $status = $idrac->virtual_media->status;
    print $status->{connected} ? "image: $status->{share}\n" : "no image\n";

    $idrac->virtual_media->connect( location => 'http://images.example.org/rescue.iso' );
    $idrac->virtual_media->connect(
      location => '//files.example.org/isos/rescue.iso',
      username => 'isos', password => $ENV{ISO_PASSWORD}
    );
    $idrac->virtual_media->disconnect;

=description

A remote ISO image the server sees as a drive: the controller fetches it from
a CIFS share, an NFS export or an HTTP(S) address. Redfish on an iDRAC 7 or 8
does not offer this (an iDRAC 8 with an Express license answers 403 for the
resource); the racadm command C<remoteimage> does, and this class is served
over it.

It needs a license: racadm names it I<Remote File Share>, and an iDRAC 8
with an Express license answers C<SWC0242> for it, which is
L<WWW::iDRAC::Error::Unsupported> here. Reading the status works without.

The status is a hash with C<connected> (an image is attached), C<share>
(its location), C<username> (the user the share is read with; the password
is never returned), and, where the license lets the controller say so,
C<attach_mode>, C<boot_once> and C<enabled> of the virtual media
configuration. A key the controller does not answer is C<undef>.

=cut

sub status_from {
  my ( $class, $remote, $config ) = @_;
  my $text = WWW::iDRAC::Racadm->text_from($remote);
  my ($state) = $text =~ /^Remote File Share is\s+(\w+)/mi;
  my %line = map { /\A(UserName|ShareName)\s*(.*?)\s*\z/ ? ( $1 => $2 ) : () } split /\n/, $text;
  my ($block) = defined $config ? WWW::iDRAC::Racadm->blocks_from($config) : ();
  my %config = map { $_->{name} => $_->{value} } $block ? @{ $block->{entries} } : ();
  my $flag = sub { defined $_[0] && length $_[0] ? ( $_[0] =~ /\A(?:enabled|1|yes)\z/i ? 1 : 0 ) : undef };
  return {
    connected   => defined $state ? ( lc $state eq 'enabled' ? 1 : 0 ) : undef,
    share       => text( $line{ShareName} ),
    username    => text( $line{UserName} ),
    attach_mode => text( $config{Attached} ),
    boot_once   => $flag->( $config{BootOnce} ),
    enabled     => $flag->( $config{Enable} )
  };
}

sub status {
  my ( $self ) = @_;
  my $remote = $self->racadm_run( status => remoteimage => '-s' );
  # the configuration needs a license the status does not
  my $config;
  if ( !eval { $config = $self->racadm->run( get => 'iDRAC.VirtualMedia' ); 1 } ) {
    my $error = $@;
    die $error unless blessed $error && $error->isa('WWW::iDRAC::Error::API');
  }
  return $self->status_from( $remote, $config );
}

=method status

    my $status = $idrac->virtual_media->status;

The state of the remote image, with the keys above. The configuration keys
come from a second command that an unlicensed controller refuses; they are
C<undef> then and the call still works.

=method status_from

    my $status = WWW::iDRAC::VirtualMedia->status_from( $remoteimage_text, $get_text );

The translation behind L</status>, without I/O. The second text may be
C<undef>.

=cut

my $LOCATION = qr{\A(?:https?://[A-Za-z0-9._:/@=,+%#-]+|//[A-Za-z0-9._:/@=,+%# -]+|[A-Za-z0-9.-]+:/(?!/)[A-Za-z0-9._:/@=,+%# -]*)\z};

sub connect {
  my ( $self, %arg ) = @_;
  my ( $location, $username, $password ) = delete @arg{qw( location username password )};
  WWW::iDRAC::Error::Validation->throw( message => 'connect takes location, username and password only' ) if %arg;
  WWW::iDRAC::Error::Validation->throw( message => 'location is //host/share/image.iso, host:/export/image.iso or an http:// or https:// address' )
    unless defined $location && !ref $location && $location =~ $LOCATION;
  WWW::iDRAC::Error::Validation->throw( message => 'username and password go together' )
    if defined $username xor defined $password;
  WWW::iDRAC::Error::Validation->throw( message => 'a CIFS share (//host/share/image.iso) needs username and password' )
    if $location =~ m{\A//} && !defined $username;
  $self->racadm_run(
    connect => remoteimage => '-c',
    ( defined $username ? ( '-u', $username, '-p', $password ) : () ),
    '-l', $location
  );
  return $self->status;
}

=method connect

    $idrac->virtual_media->connect( location => 'https://images.example.org/rescue.iso' );

Attaches an image and returns the status afterwards. C<location> is a CIFS
share C<//host/share/image.iso>, an NFS export C<host:/export/image.iso> or an
C<http://> or C<https://> address; C<username> and C<password> are for the
share, mandatory for CIFS (racadm's own help says so) and given together.
Characters racadm cannot be given safely are refused, see
L<WWW::iDRAC::Racadm/quote>, which includes a password with a quote or a
backslash in it. The password is part of no message.

Needs the license for remote file share, else
L<WWW::iDRAC::Error::Unsupported>. Not run against hardware by the author of
this distribution.

=cut

sub disconnect {
  my ( $self ) = @_;
  $self->racadm_run( disconnect => remoteimage => '-d' );
  return $self->status;
}

=method disconnect

Detaches the image and returns the status afterwards. Not run against
hardware by the author of this distribution.

=cut

sub probe_status { $_[0]->racadm_run( status => remoteimage => '-s' ) }

sub _licensed {
  my ( $self, $method ) = @_;
  return $self->racadm_run( $method => get => 'iDRAC.VirtualMedia' );
}

sub probe_connect    { $_[0]->_licensed('connect') }
sub probe_disconnect { $_[0]->_licensed('disconnect') }

=method probe_status

=method probe_connect

=method probe_disconnect

What L<WWW::iDRAC::Role::Area/supports> asks. C<status> only reads
C<remoteimage -s>. C<connect> and C<disconnect> read the virtual media
configuration, which an iDRAC 8 with an Express license refuses for want of
a license; that is how the missing license shows without trying to attach.

=cut

1;
