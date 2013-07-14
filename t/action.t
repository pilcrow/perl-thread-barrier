use strict;
use warnings;
use threads;
use threads::shared;
use Thread::Barrier;

use Test::More tests => 33;

require 't/testlib.pl';

my $i : shared = 0;

sub thr_routine {
  my $barrier = shift;
  my $me = threads->tid;

  {
    lock($i);
    is($i, 0, "[thread $me]: \$i is zero prior to barrier wait");
  }
  my $serial = $barrier->wait;
  {
    lock($i);
    is($i, 1, "[thread $me]: \$i is one after barrier wait");
  }

  $serial;
}

#
# Test ordinary action
#
{
  my $n_threads = 10;
  my @thr;

  my $b = Thread::Barrier->new($n_threads, action => sub { $i++; });

  for (1 .. $n_threads - 1) {
    push @thr, threads->create(\&thr_routine, $b);
  }
  threads->yield;
  ok_all_running(\@thr);
  is($i, 0, "[main] \$i is zero prior to barrier release");
  push @thr, threads->create(\&thr_routine, $b);
  my @serial = grep { $_ } map { $_->join } @thr;
  is(scalar @serial, 1, "[main] thread serial count correct");
  is($i, 1, "[main] \$i is one");
}

#
# Test broken action
#
{
  my %err : shared;

  my $n_threads = 5;
  my @thr;

  my $b = Thread::Barrier->new($n_threads, action => sub { die "Blargh" });
  for (1 .. $n_threads) {
    push @thr, threads->create(sub { eval { $b->wait; };
                                     ok($@, "Got expected exception: '$@'");
                                     if ($@) {
                                     lock %err;
                                     $err{ $@ =~ /Blargh/s ? 'blargh' : 'other' }++;
                                     }
                                   });
  }

  $_->join for @thr;
  lock %err;
  is($err{blargh}, 1, 'Only one thread saw action exception');
  is($err{other}, $n_threads - 1, 'All other threads saw generic error');
}

#
# Test invalid action specification
#
{
  eval { Thread::Barrier->new(2, action => "foo"); };
  ok($@, "Invalid action specification (string) raises error");
  eval { Thread::Barrier->new(2, action => {}); };
  ok($@, "Invalid action specification (hashref) raises error");
}
