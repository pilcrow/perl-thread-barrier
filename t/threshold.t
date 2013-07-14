###########################################################################
#
# threshold.t
#
# Copyright (C) 2013 Mike Pomraning mjp@cpan.org
# All rights reserved.
#
# See the README file included with the
# distribution for license information.
#
###########################################################################

use strict;
use warnings;
use threads;
use Thread::Barrier;

use Test::More tests => 11;

require 't/thr_compat.pl'; # is_running()

sub waitbar {
  my $barrier = shift;
  $barrier->wait;
}

sub snooze {
  threads->yield; select(undef, undef, undef, 0.5); threads->yield;
}


#
# Test invalid threshold
#
for my $invalid (-1, "invalid") {
  eval { Thread::Barrier->new($invalid); };
  ok($@, "Invalid threshold $invalid to constructor raises exception");

  my $b = Thread::Barrier->new(2);
  eval { $b->set_threshold($invalid); };
  ok($@, "Invalid threshold $invalid to set_threshold raises exception");
}

#
# Test lowering threshold
#
{
  my $n = 6;
  my (@barriers, @thr, $running);
  for (1 .. $n) {
    my $b = Thread::Barrier->new($n + 1);
    for (1 .. $n) {
      push @thr, threads->new(\&waitbar, $b);
    }
    push @barriers, $b;
  }

  snooze();
  is(+@thr, @barriers * $n, 'Right number of threads');
  $running = grep { $_->is_running } @thr;
  is($running, @barriers * $n, "All threads blocked on barrier");

  for (@barriers) { $_->set_threshold($n); }

  my @serials = grep {$_} map {$_->join} @thr;
  is(+@serials, $n, "Right number of serials after release");
}

#
# Test raising threshold
#
{
  my $bar = Thread::Barrier->new(2);
  my @thr = threads->create(sub { $bar->wait });

  $bar->set_threshold(3);
  push @thr, threads->create(sub { $bar->wait });

  snooze();
  my $running = grep { $_->is_running } @thr;
  is($running, 2, "Two threads waiting");

  push @thr, threads->create(sub { $bar->wait });
  snooze();
  my @serials = grep {$_} map {$_->join} @thr;
  is(+@serials, 1, "Right number of serials after release");
}

#
# Test noop threshold adjustment
#
{
  my $b = Thread::Barrier->new(2);
  my @thr = (threads->create(\&waitbar, $b));

  $b->set_threshold(2);
  snooze();

  my $running = grep { $_->is_running } @thr;
  is($running, 1, "Single waiting thread was not released");

  push @thr, threads->create(\&waitbar, $b);
  my @serials = grep { $_ } map { $_->join } @thr;
  is(+@serials, 1, "Right number of serials after release");
}
