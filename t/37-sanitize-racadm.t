#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

# What iDRACSanitizeRacadm takes out of a recorded racadm text. Invented
# values, in the forms the controllers print them.

use iDRACSanitizeRacadm;

subtest 'remoteimage -s, without an equals sign' => sub {
  my $text  = "Remote File Share is Enabled\nUserName shareuser\nPassword s3cretpw\nShareName //files.corp.example/isos/rescue.iso\n";
  my $s     = iDRACSanitizeRacadm->new;
  my $clean = $s->sanitize( { 'racadm remoteimage -s' => $text } )->{'racadm remoteimage -s'};
  unlike( $clean, qr/shareuser/, 'the user is gone' );
  unlike( $clean, qr/s3cretpw/, 'the password' );
  unlike( $clean, qr/files\.corp\.example/, 'the share and its host' );
  like( $clean, qr/^Remote File Share is Enabled$/m, 'the state stays' );
  is_deeply( [ $s->leaks( { x => $clean } ) ], [], 'and nothing is left' );
  is( iDRACSanitizeRacadm->new->sanitize( { x => "UserName \nPassword \nShareName \n" } )->{x}, "UserName \nPassword \nShareName \n", 'empty values stay empty' );
};

subtest 'a share host elsewhere' => sub {
  my $s     = iDRACSanitizeRacadm->new;
  my $clean = $s->sanitize( { a => "ShareName nfs.corp.example:/export/a.iso\n", b => "Image=nfs.corp.example:/export/b.iso\n" } );
  unlike( $clean->{b}, qr/nfs\.corp\.example/, 'the host of an NFS share is hidden in every text' );
  $clean = $s->sanitize( { a => "ShareName https://web.corp.example/a.iso\n", b => "see web.corp.example\n" } );
  unlike( $clean->{b}, qr/web\.corp\.example/, 'and of an HTTP one' );
};

subtest 'IPv6' => sub {
  my $s     = iDRACSanitizeRacadm->new;
  my $clean = $s->sanitize( { x => "IPv6 Address 1 = fd12:3456:789a::42\nLink Local = fe80::1234:56ff:fe78:9abc\nStart Time=[12:30:45]\n" } )->{x};
  unlike( $clean, qr/fd12:3456|fe80::1234/, 'addresses are replaced' );
  like( $clean, qr/2001:db8::/, 'by documentation ones' );
  like( $clean, qr/12:30:45/, 'a time is no address' );
  my @leaks = iDRACSanitizeRacadm->new->leaks( { x => "Address = fd12:3456:789a::42\n" } );
  is( scalar @leaks, 1, 'leaks finds one that is left' );
  like( $leaks[0] // '', qr/IPv6/, 'and names its kind' );
  unlike( $leaks[0] // '', qr/fd12/, 'not its value' );
};

subtest 'every kind of identifier, in the text and in the command' => sub {
  my $s = iDRACSanitizeRacadm->new;
  my $text = join "\n",
    'IP Address = 198.51.100.77', 'Gateway = 203.0.113.9', 'MAC Address = 4C:D9:8F:12:34:56', 'Other = 4c-d9-8f-12-34-57',
    'IPv6 Address 1 = 2001:db8:1::5', 'IPv6 Address 2 = fd00:abcd::1', 'Link = fe80::4ed9:8fff:fe12:3456',
    'UUID = 4c4c4544-0036-3510-8052-b8c04f4a4d32', '[Job ID=JID_123456789012]', 'Reboot JID = RID_123456789013',
    'ShareName //nas.corp.example/isos/a.iso', 'Version = 2.50.50.50', 'Start Time=[12:30:45]', '';
  my $clean = $s->sanitize( { 'racadm jobqueue view -i JID_123456789012' => $text } );
  my ( $command, $out ) = %$clean;
  unlike( $command, qr/123456789012/, 'the job id is gone from the command' );
  like( $command, qr/\Aracadm jobqueue view -i JID_\d{12}\z/, 'which keeps its shape' );
  unlike( $out, qr/198\.51\.100\.77|203\.0\.113\.9/, 'IPv4' );
  unlike( $out, qr/4c:d9|4c-d9/i, 'MAC' );
  unlike( $out, qr/fd00:abcd|fe80::4ed9/, 'IPv6 other than documentation ones' );
  like( $out, qr/2001:db8:1::5/, 'a documentation address is left, it is no real one' );
  unlike( $out, qr/4c4c4544/, 'UUID' );
  unlike( $out, qr/123456789012|123456789013/, 'job ids' );
  like( $out, qr/\[Job ID=JID_\d{12}\]/, 'in the form of one' );
  unlike( $out, qr/nas\.corp\.example/, 'the host of a share' );
  like( $out, qr/Version = 2\.50\.50\.50/, 'a version stays' );
  like( $out, qr/12:30:45/, 'a time stays' );
  is_deeply( [ $s->leaks($clean) ], [], 'and leaks finds nothing' );
  like( $s->sanitize( { x => "JID_123456789012 JID_123456789012 JID_123456789099\n" } )->{x}, qr/\AJID_(\d{12}) JID_\1 JID_(?!\1)\d{12}\n\z/, 'one id is one placeholder everywhere, another id another' );

  my $raw = { 'racadm get X' => "Address = 198.51.100.77\nMac = 4C:D9:8F:12:34:56\nJob JID_123456789012\nHost = nas.corp.example\n" };
  my @leaks = $s->leaks($raw);
  ok( ( grep { /IPv4/ } @leaks ), 'leaks sees an IPv4' );
  ok( ( grep { /MAC/ } @leaks ), 'and a MAC' );
  my @none = iDRACSanitizeRacadm->new->leaks( { 'racadm get X' => "Value = 2001:db8::1\n" } );
  is_deeply( \@none, [], 'a documentation address is no leak' );
  my @fe80 = iDRACSanitizeRacadm->new->leaks( { x => "Link = fe80::1\n" } );
  is( scalar @fe80, 1, 'a link-local one is' );
};

done_testing;
