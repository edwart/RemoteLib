#!/usr/bin/perl

use strict;
use warnings;
use RemoteLib qw/{server=>miltonkeynes.pm, port=>7777}/;
use Tk;

my $mw = new MainWindow;
$mw->Label(-text => 'Hello World')->pack;
$mw->Button(-text => 'Exit', -command => sub { $mw->destroy; exit(0) })->pack;
MainLoop;
