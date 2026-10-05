#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

for (qw(
  WWW::iDRAC
  WWW::iDRAC::Capabilities
  WWW::iDRAC::Error
  WWW::iDRAC::Error::API
  WWW::iDRAC::Error::Network
  WWW::iDRAC::Error::Unsupported
  WWW::iDRAC::Error::Validation
  WWW::iDRAC::Logs
  WWW::iDRAC::Manager
  WWW::iDRAC::Power
  WWW::iDRAC::Redfish
  WWW::iDRAC::Role::Capability
  WWW::iDRAC::Role::HTTP
  WWW::iDRAC::Sensors
  WWW::iDRAC::System
  WWW::iDRAC::Util
)) {
  use_ok($_);
}

done_testing;
