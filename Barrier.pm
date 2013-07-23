###########################################################################
# $Id: Barrier.pm,v 1.9 2007/03/25 08:20:07 wendigo Exp $
###########################################################################
#
# Barrier.pm
#
# RCS Revision: $Revision: 1.9 $
# Date: $Date: 2007/03/25 08:20:07 $
#
# Copyright 2002-2003, 2005, 2007 Mark Rogaski, mrogaski@cpan.org
#
# See the README file included with the
# distribution for license information.
#
###########################################################################

package Thread::Barrier;

use 5.008;
use strict;
use warnings;

use threads;
use threads::shared;

our $VERSION = '0.300_01';

###########################################################################
# Public Methods
###########################################################################

#
# new - creates a new Thread::Barrier object
#
# Arguments:
#
# threshold (opt)
#   Specifies the required number of threads that
#   must block on the barrier before it is released.
#   Default value is 0.
#
# Returns a Thread::Barrier object on success, dies on failure.
#
sub new {
    my ($class, $threshold, %opts) = @_;

    # threads::shared 1.43 (perl 5.18.0) does not yet support shared
    # CODE refs, which would be obvious/ideal for our 'action' support.
    # So, our Thread::Barrier object isn't itself shared, but one of
    # its members is.
    #
    # Object structure (ARRAY ref):
    #
    #   [   {barrier implementation},    <-- shared
    #       \&optional_coderef        ]  <-- non-shared
    #

    my $self = bless [], $class;

    $self->[0] = &share({});
    %{$self->[0]} = (
        threshold           => 0,    # threads required to release barrier
        count               => 0,    # number of threads blocking on barrier
        generation          => 0,    # incremented when barrier is released
       #broken              => 0,    # true if broken
       #first_released_$gen => 1,    # if present, $gen was just released
    );

    $self->set_threshold($threshold) if $threshold; # may die
    if ($opts{action}) {
      _confess("Invalid action parameter to $class->new")
        unless ref($opts{action}) eq 'CODE';
      $self->[1] = $opts{action};
    }

    return $self;
}


#
# init - set the threshold value for the barrier
#
# *** DEPRECATED ***
#
# Arguments:
#
# threshold
#   Specifies the required number of threads that 
#   must block on the barrier before it is released.
# 
# Returns the passed argument.
#
sub init {
    my($self, $threshold) = @_;
    $self->set_threshold($threshold);
    return $threshold;
}


#
# wait - block until a sufficient number of threads have reached the barrier
#
# Arguments:
#
# none
#
# Returns true to one of threads released upon barrier reset, false to
# all others.
#
sub wait {
    my ($self, $timeo) = @_;
    my ($bar, $act) = @$self; # Unwrap our actual barrier and action (if any)
    my ($gen, $i);

    $timeo = $self->_normalize_timeout($timeo)
      if defined($timeo);

    lock $bar;

    $gen = $bar->{generation};
    $i   = $bar->{count}++;

    if (! $self->_try_release) {
        unless (defined $timeo) {
          # block
          while ($bar->{generation} == $gen and not $bar->{broken}) {
            cond_wait($bar);
          }
        } else {
          while ($bar->{generation} == $gen and not $bar->{broken}) {
            last if !cond_timedwait($bar, $timeo);
          }
          $bar->{broken} = 1 if $bar->{generation} == $gen;
        }
    }

    # Are we the first awake from our generation?  Run action if any
    if (delete $bar->{"first_released_${gen}"} and $act) {
      my $ok = eval { $act->(); 1; };
      if (! $ok) {
        $bar->{broken} = 1;
        die($@ || "Barrier action failed");
      }
    } elsif ($bar->{broken}) {
      _croak("Barrier broken");
    }

    # In our implementation, the first one to arrive gets the serial
    # indicator
    return ($i == 0);
}


#
# set_threshold - adjust the barrier's threshold, possibly releasing it
#                  if enough threads are blocking.
#
# Arguments:
#
# threshold
#   Specifies the required number of threads that
#   must block on the barrier before it is released.
#
# Returns true if barrier is released, false otherwise.
#
sub set_threshold {
    my($self, $threshold) = @_;
    my $err;

    # validate threshold
    for ($threshold) {
        $err = "no argument supplied", last unless defined $_;
        $err = "invalid argument supplied", last if /[^0-9]/;
    }
    if ($err) {
        local $Carp::CarpLevel = 1;
        _confess($err);
    }

    # apply new threshold, possibly releasing barrier
    lock $self->[0];
    $self->[0]->{threshold} = $threshold;

    # check for release condition
    $self->_try_release;
}


#
# threshold - accessor for debugging purposes
#
sub threshold {
    my $bar = shift->[0];
    lock $bar;
    return $bar->{threshold};
}


#
# count - accessor for debugging purposes
#
sub count {
    my $bar = shift->[0];
    lock $bar;
    return $bar->{count};
}


###########################################################################
# Private Methods
###########################################################################

sub _confess {
  require Carp;
  goto &Carp::confess;
}

sub _croak {
  require Carp;
  goto &Carp::croak;
}

#
# _try_release - release the barrier if a sufficient number of threads
#                have reached the barrier.
#                N.B.:  Assumes the barrier is locked
#
# Arguments:
#
#   none
#
# Returns true if barrier is released, false otherwise.
#
sub _try_release {
    my $bar = shift->[0];

    return undef if $bar->{count} < $bar->{threshold};

    # reset barrier and release
    my $gen = $bar->{generation}++;
    $bar->{"first_released_${gen}"} = 1;
    $bar->{count} = 0;

    cond_broadcast($bar);
    return 1;
}

sub _normalize_timeout {
  my ($self, $timeo) = @_;
  $timeo =~ /^\d+(?:\.\d+)*$/
    or _croak("Invalid timeout specification ($timeo)");
  $timeo += time();
}

1;
__END__

=head1 NAME

Thread::Barrier - thread execution barrier

=head1 SYNOPSIS

  use Thread::Barrier;

  # Common case
  #
  my $br = Thread::Barrier->new($threshold);
  ...
  $br->wait();               # Wait for $threshold threads to arrive

  if ($br->wait()) {         # Same, but one thread will then log
    log("Everyone arrived");
  }

  # Barrier with action
  #
  my $coderef = sub { ... };
  my $br = Thread::Barrier->new($threshold, action => $coderef);
  ...
  $br->wait();               # $coderef will have run before any threads
                             # return from wait()

=head1 ABSTRACT

Execution barrier for multiple threads.

=head1 DESCRIPTION

Thread barriers provide a mechanism for synchronization of multiple threads.
All threads issuing a C<wait> on the barrier will block until the count
of waiting threads meets some threshold value.  When the threshold is met, the
threads will be released and the barrier reset, ready to be used again.  This
mechanism proves quite useful in situations where processing progresses in
stages and completion of the current stage by all threads is the entry
criteria for the next stage.

=head1 METHODS

=over 4

=item new THRESHOLD

=item new THRESHOLD OPTION => VALUE

C<new> creates a new barrier with a threshold of C<THRESHOLD>.

Optional parameters may be specified in a hash-like fashion.  At present
the only supported OPTION is 'action', which specifies a code reference to
be run when the last thread has arrived but before any threads return from
L</wait>.  Precisely which thread runs the code reference is unspecified.

=item set_threshold COUNT

C<set_threshold> specifies the threshold count for the barrier, which must
be zero or a positive integer.  (Note that a threshold of zero or one is
rather a degenerate case barrier.)  If the new value of C<COUNT> is less
than or equal to the number of threads blocked on the barrier, the barrier
is released.

Returns true if the barrier is released because of the adjustment, false
otherwise.

=item wait

C<wait> causes the thread to block until the number of threads blocking on
the barrier meets the threshold.  When the blocked threads are released, the
barrier is reset to its initial state and ready for re-use.

This method returns a true value to one of the released threads, and false to
any and all others.  Precisely which thread receives the true value is
unspecified, however.

=item threshold

Returns the currently configured threshold.

=item count

Returns the instantaneous count of threads blocking on the barrier.

B<WARNING:  This is an accessor method that is intended for debugging
purposes only, the lock on the barrier object is released when the
method returns.>

=back


=head1 EXAMPLES

The return code from L</wait> may be used to serialize a single-threaded
action upon release, executing the action only after all threads have
arrived at (and are released from) the barrier:

    sub worker {            # Thr routine: threads->create(\&worker, ...)
        my $br = shift;     # $br->isa('Thread::Barrier')

        get_ready();

        if ($br->wait) {
            do_log("All ready");    # Called only once
        }

       do_work();
    }

Of course, the operating system may schedule the single-threaded action to
occur at any time.  That is, in the example above, do_log() may run before,
during or after other released threads' calls to do_work().  To further
serialize this action to complete before peer threads do anything else,
simply re-use the same barrier:

    sub worker {
        my $br = shift;

        get_ready();

        if ($br->wait) {
            init_globals();     # Must run after all get_ready()
                                # calls complete
        }

        $br->wait;              # Prevents do_work() from running
                                # before init_globals() finishes.
        do_work();
    }


=head1 SEE ALSO

L<perlthrtut>.


=head1 NOTES

Many thanks to Michael Pomraning for providing a workaround for a race
condition in the C<wait()> method that also helped to clean up the code and
for additional suggestions.


=head1 AUTHOR

Mark Rogaski, E<lt>mrogaski@cpan.orgE<gt>
Mike Pomraning, E<lt>mjp@cpan.orgE<gt>

If you find this module useful or have any questions, comments, or
suggestions please send an email message.


=head1 COPYRIGHT AND LICENSE

Copyright 2002-2003, 2005, 2007 by Mark Rogaski, mrogaski@cpan.org;
all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the README file distributed with
Perl for further details.


=cut

