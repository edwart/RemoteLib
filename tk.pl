#!/usr/bin/perl

use strict;
use warnings;
use Tk '804.031';

my $mw = new MainWindow;
$mw->Label(-text => 'Hello World')->pack;
$mw->Button(-text => 'Exit', -command => sub { $mw->destroy; exit(0) })->pack;
MainLoop;
