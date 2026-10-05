package WWW::iDRAC::Util;

# ABSTRACT: The small translations every part of WWW::iDRAC needs

use strict;
use warnings;
use Exporter qw( import );
use Scalar::Util qw( looks_like_number );

our $VERSION = '0.001';

our @EXPORT_OK = qw( text number health_of state_of list_of );

=synopsis

    use WWW::iDRAC::Util qw( text number health_of state_of list_of );

=description

Pure functions that turn a value out of a Redfish document into what
WWW::iDRAC returns. None of them does I/O, none of them warns on a value
that is missing.

=cut

sub text {
  my ( $value ) = @_;
  return undef if !defined $value || ref $value;
  ( my $text = $value ) =~ s/\A\s+|\s+\z//g;
  return length $text ? $text : undef;
}

=func text

A string without the padding some firmware adds, or C<undef> for nothing, an
empty string and anything that is not a plain value.

=cut

sub number {
  my ( $value ) = @_;
  return defined $value && !ref $value && looks_like_number($value) ? $value + 0 : undef;
}

=func number

A number, or C<undef> for anything that is none.

=cut

my %HEALTH = ( ok => 'ok', warning => 'warning', critical => 'critical' );

sub health_of {
  my ( $status ) = @_;
  my $health = ref $status eq 'HASH' ? text( $status->{Health} ) : undef;
  return defined $health ? $HEALTH{ lc $health } : undef;
}

=func health_of

    my $health = health_of( $doc->{Status} );

C<ok>, C<warning> or C<critical> out of a Redfish C<Status>, or C<undef> when
the controller does not say.

=cut

sub state_of {
  my ( $value ) = @_;
  my $state = text($value) // return undef;
  $state =~ s/(?<=[a-z])(?=[A-Z])/_/g;
  return lc $state;
}

=func state_of

A Redfish state in lower case with underscores: C<On> becomes C<on>,
C<PoweringOn> becomes C<powering_on>.

=cut

sub list_of {
  my ( $value ) = @_;
  return grep { ref $_ eq 'HASH' } ref $value eq 'ARRAY' ? @$value : ();
}

=func list_of

The hashes of a list, or nothing when there is no list.

=cut

1;
