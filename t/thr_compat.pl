#!/usr/bin/env perl

package Ad::Hoc::Thread::Compat;

use strict;
use warnings;
use threads;
use threads::shared;

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
