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

use Test::More tests => 53;

require 't/testlib.pl';

my $i : shared = 0;

sub thr_patient {
  my ($barrier, $timeout) = @_;
  my $tid = threads->tid;

  no warnings 'uninitialized';

  {
    lock($i);
    is($i, 0, "[$tid]: \$i is zero before barrier wait($timeout)");
  }
  my $serial = $barrier->wait($timeout);
  {
    lock($i);
    is($i, 1, "[$tid]: \$i is one after barrier wait($timeout)");
  }

  $serial;
}

sub thr_timeout {
  my ($barrier, $timeout) = @_;
  my $tid = threads->tid;

  no warnings 'uninitialized';

  {
    lock($i);
    is($i, 0, "[$tid]: \$i is zero before barrier wait($timeout)");
  }
  my $serial = eval { $barrier->wait($timeout) };
  ok($@ =~ /broken/, "[$tid]: timed out with Barrier broken exception")
    or diag("\$\@ was: $@");
  {
    lock($i);
    is($i, 0, "[$tid]: \$i still zero after timeout($timeout)");
  }
  $serial;
}

#
# Undef timeout, 10 sec timeout
#
for my $timeout (undef, 10) {

  { lock $i; $i = 0; }

  my $n       = 5;
  my $barrier = Thread::Barrier->new($n, Action => sub { $i++; });
  my @threads = nthreads($n - 1, \&thr_patient, $barrier, $timeout);

  select(undef, undef, undef, 1);
  ok_all_running(\@threads);

  is($i, 0, "\$i is zero before barrier release");

  push @threads, threads->create(\&thr_patient, $barrier, $timeout);

  my @serial = grep { $_ } map { $_->join } @threads;
  is(scalar @serial, 1, "thread serial count correct");
  is($i, 1, "\$i is one");
}

#
# Timeout
#
{
  { lock($i); $i = 0; }
  my $n       = 5;
  my $barrier = Thread::Barrier->new($n, Action => sub { $i++ });
  my @threads = nthreads($n - 1, \&thr_timeout, $barrier, 3);

  my @serial  = grep { $_ } map { $_->join } @threads;
  is(scalar @serial, 0, "no serial return upon timeout");
}

#
# Long-running action does _not_ cause a timeout
#
{
  { lock($i); $i = 0; }
  my $n       = 5;
  my $barrier = Thread::Barrier->new($n, Action => sub { zzz(10); $i++; });
  my @threads = nthreads($n - 1, \&thr_patient, $barrier, 5);

  push @threads, threads->create(sub { $barrier->wait });

  my @serial  = grep { $_ } map { $_->join } @threads;
  is(scalar @serial, 1, "serial count correct");
}

#
# Test invalid timeout specification
#
{
  my @invalid = (-1, "a string", []);
  my $barrier = Thread::Barrier->new(2);

  for my $timeout (@invalid) {
    my $r = threads->create(sub { eval { $barrier->wait($timeout) }; "$@"; })->join;
    ok($r =~ /invalid/i, "Invalid timeout throws exception");
  }
}
