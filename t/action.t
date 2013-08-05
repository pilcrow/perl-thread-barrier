use strict;
use warnings;
use Config;
BEGIN {
  unless ($Config{useithreads}) {
    print "1..0 # SKIP perl not compiled with 'useithreads'\n";
    exit 0;
  }
}
use threads;
use threads::shared;
use Thread::Barrier;

use Test::More tests => 28;

require 't/testlib.pl';

my $i : shared = 0;

sub thr_routine {
  my $barrier = shift;
  my $tid = threads->tid;

  {
    lock($i);
    is($i, 0, "[$tid]: \$i is zero before barrier wait");
  }
  my $serial = $barrier->wait;
  {
    lock($i);
    is($i, 1, "[$tid]: \$i is one after barrier wait");
  }

  $serial;
}

#
# Test ordinary action
#
{
  my $n       = 10;
  my $barrier = Thread::Barrier->new($n, Action => sub { $i++; });
  my @threads = nthreads($n - 1, \&thr_routine, $barrier);

  threads->yield;
  ok_all_running(\@threads);
  is($i, 0, "\$i is zero before barrier release");

  push @threads, threads->create(\&thr_routine, $barrier);
  my @serial = grep { $_ } map { $_->join } @threads;
  is(scalar @serial, 1, "thread serial count correct");
  is($i, 1, "\$i is one");
}

#
# Test broken action
#
{
  my $n       = 5;
  my $barrier = Thread::Barrier->new($n, Action => sub { die "Blargh" });
  my @threads = nthreads($n, sub { eval {$barrier->wait}; "$@"; });

  my @ret     = map  { $_->join }   @threads;
  my $blarghs = grep { /Blargh/s }  @ret;
  my $brokens = grep { /broken/is } @ret;

  is($blarghs, 1,      "Got one custom exception");
  is($brokens, $n - 1, "Got other generic broken exceptions");
}

#
# Test invalid action specification
#
{
  eval { Thread::Barrier->new(2, Action => "foo"); };
  ok($@, "Invalid action specification (string) raises error");
  eval { Thread::Barrier->new(2, Action => {}); };
  ok($@, "Invalid action specification (hashref) raises error");
}
