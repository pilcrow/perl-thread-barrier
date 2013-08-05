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

use Test::More tests => 20;

require 't/testlib.pl';

my $i : shared = 0;
my %serial : shared;

sub thr_timeout {
  my ($barrier, $timeout) = @_;
  my $tid = threads->tid;

  no warnings 'uninitialized';

  {
    lock($i);
    is($i, 0, "[$tid]: \$i is zero before barrier wait($timeout)");
  }
  my $serial;
  my $ok = eval { $serial = $barrier->wait($timeout); 1; };

  ok($ok, "No exception thrown with RaiseError => 0")
    or diag("Exception was $@");
  ok(!defined($serial), "Serial undefined");
  {
    lock($i);
    is($i, 0, "[$tid]: \$i still zero after timeout($timeout)");
  }
  $serial;
}

sub thr_badaction {
  my $barrier = shift;
  my $tid = threads->tid;

  my $serial;
  my $ok = eval { $serial = $barrier->wait; 1; };

  lock %serial;
  if (!$ok) { # exception thrown
    $serial{exception}++;
  } else {
    $serial{undef}++ unless defined($serial);
  }

  $serial;
}

#
# Timeout
#
{
  { lock($i); $i = 0; }
  my $n       = 5;
  my $barrier = Thread::Barrier->new($n, RaiseError => 0, Action => sub { $i++ });
  my @threads = nthreads($n - 1, \&thr_timeout, $barrier, 3);

  my @serial  = grep { $_ } map { $_->join } @threads;
  is(scalar @serial, 0, "no serial return upon timeout");
}

#
# Bad action
#
{
  { lock($i); $i = 0; }
  my $n       = 5;
  my $barrier = Thread::Barrier->new($n, RaiseError => 0,
                                         Action => sub { die "Aaargh" });
  my @threads = nthreads($n, \&thr_badaction, $barrier);

  my @serial  = grep { $_ } map { $_->join } @threads;
  is(scalar @serial, 0, "no serial return with bad action");
  is($serial{exception}, 1, "a single waiter die()d");
  is($serial{undef}, $n - 1, "other waiters got undef")
}
