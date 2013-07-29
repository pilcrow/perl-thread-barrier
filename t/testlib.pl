#!/usr/bin/env perl

use strict;
use warnings;
use threads;
use threads::shared;
use Test::More qw();

sub zzz {
  select(undef, undef, undef, $_[0]);
}

sub nthreads {
  my $n = shift;
  map { threads->create(@_) } 1 .. $n;
}

sub ok_all_running(\@;$) {
  my ($thr, $msg) = @_;
  my $expected = @$thr;
  my $running = grep { $_->is_running } @$thr;
  is($running, $expected, $msg || "$running threads running (expected $expected)");
}

package Ad::Hoc::Thread::Compat;

our %Running : shared;

if (! threads->can('is_running')) { # threads->VERSION < 1.34
  my $create  = \&threads::create;
  my $destroy = \&threads::DESTROY;

  no strict 'refs';
  *threads::create = *threads::new = sub {
    my $thr = $create->(@_);
    if ($thr) {
      lock %Running;
      $Running{ $thr->tid } = 1;
    }
    $thr;
  };

  *threads::is_running = sub {
    my $self = shift;
    lock %Running;
    $Running{ $self->tid };
  };

  *threads::DESTROY = sub {
    my $self = shift;
    lock %Running;
    delete $Running{ $self->tid };
    goto &$destroy;
  };
}

1;
