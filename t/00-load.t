#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

for (qw(
  WWW::iDRAC
  WWW::iDRAC::Bios
  WWW::iDRAC::Capabilities
  WWW::iDRAC::Error
  WWW::iDRAC::Error::API
  WWW::iDRAC::Error::Network
  WWW::iDRAC::Error::Unsupported
  WWW::iDRAC::Error::Validation
  WWW::iDRAC::Jobs
  WWW::iDRAC::Logs
  WWW::iDRAC::Manager
  WWW::iDRAC::Power
  WWW::iDRAC::Racadm
  WWW::iDRAC::Racadm::SSH
  WWW::iDRAC::Redfish
  WWW::iDRAC::Role::Area
  WWW::iDRAC::Role::Capability
  WWW::iDRAC::Role::HTTP
  WWW::iDRAC::Role::Racadm
  WWW::iDRAC::Role::Transport
  WWW::iDRAC::Sensors
  WWW::iDRAC::System
  WWW::iDRAC::Util
  WWW::iDRAC::VirtualMedia
)) {
  use_ok($_);
}

done_testing;
