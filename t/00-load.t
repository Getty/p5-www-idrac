#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

for (qw(
  WWW::iDRAC
  WWW::iDRAC::Error
  WWW::iDRAC::Error::API
  WWW::iDRAC::Error::Network
  WWW::iDRAC::Error::Unsupported
  WWW::iDRAC::Error::Validation
  WWW::iDRAC::Redfish
  WWW::iDRAC::Role::HTTP
)) {
  use_ok($_);
}

done_testing;
