package WWW::iDRAC::Bios;

# ABSTRACT: BIOS attributes of the server, read and staged over racadm

use Moo;
use Scalar::Util qw( blessed );
use WWW::iDRAC::Error::Validation;
use WWW::iDRAC::Racadm;
use WWW::iDRAC::Util qw( text );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'bios' }

with 'WWW::iDRAC::Role::Racadm';

=synopsis

    print "$_\n" for @{ $idrac->bios->groups };

    print $_->{name}, ' = ', $_->{value} // '', "\n" for @{ $idrac->bios->group('BiosBootSettings') };
    print $idrac->bios->get('BiosBootSettings.BootMode'), "\n";

    # staged, then made a job; it takes effect when the server restarts
    $idrac->bios->set( 'BiosBootSettings.BootMode' => 'Bios' );
    my $job = $idrac->bios->commit( reboot => 'none' );
    my $done = $idrac->jobs->wait( $job->{job_id}, timeout => 900 );

=description

The BIOS of the server, as the controller exposes it: attributes in groups,
named C<Group.Attribute> as racadm names them (C<BiosBootSettings.BootMode>).
Redfish on an iDRAC 7 or 8 has no BIOS attributes; this class is served over
racadm, see L<WWW::iDRAC::Racadm> for what that needs.

Reading is immediate. Writing is not: a changed attribute is only I<pending>
until a job for the BIOS exists, and the job runs when the server restarts.
L</set> stages, L</commit> creates the job, and L<WWW::iDRAC::Jobs> follows
it. Nothing here restarts the server unless C<commit> is asked to.

Which groups and attributes exist depends on the server and its BIOS; an
attribute the BIOS shows read-only (racadm marks it C<#>) is read-only here.

=cut

my $GROUP = qr/\A[A-Za-z][A-Za-z0-9]*\z/;
my $NAME  = qr/\A([A-Za-z][A-Za-z0-9]*)\.([A-Za-z][A-Za-z0-9]*)\z/;

sub _group_name {
  my ( $class, $group ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'a BIOS group is a plain name like BiosBootSettings' )
    unless defined $group && !ref $group && $group =~ $GROUP;
  return $group;
}

sub _attribute_name {
  my ( $class, $name ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'a BIOS attribute is named Group.Attribute, like BiosBootSettings.BootMode' )
    unless defined $name && !ref $name && $name =~ $NAME;
  return ( $1, $2 );
}

sub groups_from {
  my ( $class, $raw ) = @_;
  return [ grep { /\A[A-Za-z][A-Za-z0-9]*\z/ } map { s/\A\s+|\s+\z//gr } split /\n/, WWW::iDRAC::Racadm->text_from($raw) ];
}

sub groups {
  my ( $self ) = @_;
  my $text;
  if ( !eval { $text = $self->racadm_run( groups => get => 'BIOS' ); 1 } ) {
    my $error = $@;
    die $error unless blessed $error && $error->isa('WWW::iDRAC::Error::API');
    # an iDRAC 7 answers "Unable to perform requested operation"
    $self->unsupported( groups => 'the controller does not list its BIOS groups ('.$error->api_message.')' );
  }
  my $groups = $self->groups_from($text);
  $self->unsupported( groups => 'the controller lists no BIOS groups' ) unless @$groups;
  return $groups;
}

=method groups

The names of the BIOS groups, for example C<BiosBootSettings> and
C<ProcSettings>. Measured on an iDRAC 8; an iDRAC 7 does not list its groups
and answers C<Unsupported>, but serves each group by name.

=method groups_from

    my $groups = WWW::iDRAC::Bios->groups_from($text);

The translation behind L</groups>, without I/O.

=cut

sub group_from {
  my ( $class, $raw ) = @_;
  my ($block) = WWW::iDRAC::Racadm->blocks_from($raw);
  return undef unless $block;
  return {
    fqdd       => ( $block->{id} =~ /\A([^#]+)#/ )[0],
    attributes => [ map { { name => $_->{name}, value => text( $_->{value} ), read_only => $_->{read_only} } } @{ $block->{entries} } ]
  };
}

sub group {
  my ( $self, $group ) = @_;
  $self->_group_name($group);
  my $read = $self->group_from( $self->racadm_run( group => get => 'BIOS.'.$group ) );
  $self->unsupported( group => 'the controller answered without attributes for BIOS.'.$group ) unless $read;
  return $read->{attributes};
}

=method group

    my $attributes = $idrac->bios->group('BiosBootSettings');
    # [ { name => 'BootMode', value => 'Uefi', read_only => 0 }, ... ]

The attributes of one group, in the order the BIOS lists them: C<name>,
C<value> (C<undef> where the attribute is empty) and C<read_only>. A group
the BIOS does not have is L<WWW::iDRAC::Error::API> with C<is_not_found>.

=method group_from

    my $group = WWW::iDRAC::Bios->group_from($text);    # { fqdd => 'BIOS.Setup.1-1', attributes => [...] }

The translation behind L</group>, without I/O: the attributes and the
component name the controller gives for them, or C<undef> when the text has
no group.

=cut

sub _entry {
  my ( $self, $method, $name ) = @_;
  my ( $group, $attribute ) = $self->_attribute_name($name);
  my $read = $self->group_from( $self->racadm_run( $method => get => 'BIOS.'.$group.'.'.$attribute ) );
  $self->unsupported( $method => 'the controller answered without BIOS.'.$name ) unless $read;
  my ($entry) = grep { $_->{name} eq $attribute } @{ $read->{attributes} };
  $self->unsupported( $method => 'the controller answered without BIOS.'.$name ) unless $entry;
  return ( $entry, $read->{fqdd} );
}

sub get {
  my ( $self, $name ) = @_;
  my ($entry) = $self->_entry( get => $name );
  return $entry->{value};
}

=method get

    my $mode = $idrac->bios->get('BiosBootSettings.BootMode');

The value of one attribute, C<undef> when it is empty. Where the controller
has a staged change that is not applied yet, this is the value now, not the
pending one. An attribute the BIOS does not have is
L<WWW::iDRAC::Error::API> with C<is_not_found>.

=cut

sub set {
  my ( $self, $name, $value ) = @_;
  $self->_attribute_name($name);
  # the same limits as for any argument sent to racadm, and before anything is read
  WWW::iDRAC::Racadm->quote($value);
  my ( $entry, $fqdd ) = $self->_entry( set => $name );
  WWW::iDRAC::Error::Validation->throw( message => 'BIOS.'.$name.' is read-only' ) if $entry->{read_only};
  my $answer = $self->racadm_run( set => set => 'BIOS.'.$name, $value );
  return {
    name     => $name,
    value    => $value,
    previous => $entry->{value},
    fqdd     => $fqdd,
    pending  => $self->pending_from($answer)
  };
}

sub pending_from {
  my ( $class, $raw ) = @_;
  return WWW::iDRAC::Racadm->text_from($raw) =~ /\bpending\b/i ? 1 : 0;
}

=method set

    my $staged = $idrac->bios->set( 'BiosBootSettings.BootMode' => 'Bios' );

Stages a new value and returns C<name>, C<value>, C<previous> (the value
before), C<fqdd> (the BIOS component the job in L</commit> is made for) and
C<pending>, true when racadm said the change is pending. Nothing changes in
the running BIOS until L</commit> and a restart.

The attribute is read first: one that does not exist is
L<WWW::iDRAC::Error::API> with C<is_not_found>, one the BIOS shows read-only
is L<WWW::iDRAC::Error::Validation>, in both cases before anything is
written. A value with a character racadm cannot be given safely, see
L<WWW::iDRAC::Racadm/quote>, is C<Validation> too. The BIOS decides whether
the value itself is allowed; its refusal is L<WWW::iDRAC::Error::API>.

=method pending_from

    my $pending = WWW::iDRAC::Bios->pending_from($text);

1 when the text racadm printed after a C<set> says the change is pending.
No I/O.

=cut

my %REBOOT = map { $_ => 1 } qw( none graceful forced pwrcycle );

sub commit {
  my ( $self, %arg ) = @_;
  my $reboot = delete $arg{reboot} // 'none';
  WWW::iDRAC::Error::Validation->throw( message => 'commit takes reboot only' ) if %arg;
  WWW::iDRAC::Error::Validation->throw( message => 'reboot is none, graceful, forced or pwrcycle' )
    unless !ref $reboot && $REBOOT{$reboot};
  my $fqdd = $self->fqdd;
  my $answer = $self->racadm_run( commit => jobqueue => create => $fqdd, '-r', $reboot, '-s', 'TIME_NOW' );
  return $self->job_from( $answer, $fqdd );
}

sub job_from {
  my ( $class, $raw, $fqdd ) = @_;
  my $text = WWW::iDRAC::Racadm->text_from($raw);
  my ($commit) = $text =~ /\b(JID_[0-9]+)\b/;
  my ($reboot) = $text =~ /\b(RID_[0-9]+)\b/;
  return { job_id => $commit, reboot_job_id => $reboot, fqdd => $fqdd };
}

sub fqdd {
  my ( $self ) = @_;
  my $read = $self->group_from( $self->racadm_run( commit => get => 'BIOS.BiosBootSettings' ) );
  return $read->{fqdd} // $self->unsupported( commit => 'the controller names no BIOS component' );
}

=method commit

    my $job = $idrac->bios->commit;                       # no restart
    my $job = $idrac->bios->commit( reboot => 'graceful' );

Creates the job that applies the staged BIOS changes and returns C<job_id>
(the commit job), C<reboot_job_id> (the restart job, when C<reboot> asked for
one, else C<undef>) and C<fqdd>. C<reboot> is C<none>, the default: the job
waits for the next restart, which is what the caller decides; C<graceful>,
C<forced> or C<pwrcycle> restarts the server, with the effect those words
have for racadm. Follow the job with L<WWW::iDRAC::Jobs/wait>.

=method job_from

    my $job = WWW::iDRAC::Bios->job_from( $text, $fqdd );

The job identifiers out of the text racadm printed when it created the job,
without I/O.

=method fqdd

The name of the BIOS component as the controller gives it, for example
C<BIOS.Setup.1-1>, read from the boot settings.

=cut

sub probe_groups { $_[0]->groups }

sub probe_group { $_[0]->group('BiosBootSettings') }

sub probe_get { $_[0]->_entry( get => 'BiosBootSettings.BootMode' ) }

sub _writable {
  my ( $self, $method ) = @_;
  my $attributes = $self->group('BiosBootSettings');
  $self->unsupported( $method => 'the BIOS shows no attribute that is not read-only' )
    unless grep { !$_->{read_only} } @$attributes;
  return;
}

sub probe_set    { $_[0]->_writable('set') }
sub probe_commit { $_[0]->_writable('commit') }

=method probe_groups

=method probe_group

=method probe_get

=method probe_set

=method probe_commit

What L<WWW::iDRAC::Role::Area/supports> asks. The probes only read: C<set>
and C<commit> are supported when the BIOS offers at least one attribute that
is not read-only, which is as far as a reading can tell.

=cut

1;
