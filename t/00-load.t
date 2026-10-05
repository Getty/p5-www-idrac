#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

for (qw(
  WWW::iDRAC
)) {
  use_ok($_);
}

done_testing;
