###########################################################################
#
# See the README file included with the
# distribution for license information.
#
###########################################################################

package Thread::Barrier;

use 5.008;
use strict;
use warnings;

use threads::shared;

our $VERSION = '0.300_02';
$VERSION = eval $VERSION;

###########################################################################
# Public Methods
###########################################################################

#
# new - creates a new Thread::Barrier object
#
# Arguments:
#
# threshold
#   Specifies the required number of threads that
#   must block on the barrier before it is released.
# opt => val ...
#   Optional arguments to new()
#
# Returns a Thread::Barrier object on success, dies on failure.
#
sub new {
    my ($class, $threshold, %opts) = @_;
    $opts{RaiseError} = 1 unless exists $opts{RaiseError};

    # threads::shared 1.43 (perl 5.18.0) does not yet support shared
    # CODE refs, which would be obvious/ideal for our 'Action' support.
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
    while (my ($opt, $val) = each(%opts)) {
      if ($opt eq 'Action' and defined($val)) {
        _confess("Invalid Action parameter to $class->new")
        unless ref($val) eq 'CODE';
        $self->[1] = $val;
        next;
      }
      if ($opt eq 'RaiseError') {
        $self->[0]->{RaiseError} = !!$val;
        next;
      }
      _confess("Unrecognized parameter '$opt' to $class->new");
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
    my ($bar, $act) = @$self; # Unwrap our actual barrier and Action (if any)
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

    # Are we the first awake from our generation?  Run Action if any
    if (delete $bar->{"first_released_${gen}"} and $act) {
      my $ok = eval { $act->(); 1; };
      if (! $ok) {
        $bar->{broken} = 1;
        die($@ || "Barrier action failed");
      }
    } elsif ($bar->{broken}) {
      _croak("Barrier broken") if $bar->{RaiseError};
      return undef;
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
        no warnings 'once';
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

  my $br = Thread::Barrier->new($n);
  ...
  $br->wait();               # Wait for $n threads to arrive, then all
                             # are released at the same time.
  ...
  if ($br->wait()) {         # As above, but one and only one thread
    log("Everyone arrived"); # logs after release.
  }

  my $br = Thread::Barrier->new($n, Action => \&mysub);
  ...
  $br->wait();               # mysub() will be called once after $n
                             # threads arrive but before any are
                             # released.

  $br->wait($n);             # Wait for $n threads, but not forever.

=head1 ABSTRACT

Execution barrier for multiple threads.

=head1 DESCRIPTION

A barrier allows a set of threads to wait for each other to arrive at the same
point of execution, proceeding only when all of them have arrived.  After
releasing the threads, a Thread::Barrier object is reset and ready to be
used again.

Sometimes it is convenient to have one thread from the waiting set perform
some action when all parties have arrived.  Thread::Barrier objects support
this functionality in two ways, either I<just before> release (via an
'Action' parameter to L</new>) or I<just after> release (via the serialized
return value from L</wait>).

Waiting threads may also pass a timeout value to L</wait> if they don't wish
to block indefinitely.

=head1 METHODS

=over 4

=item new THRESHOLD

=item new THRESHOLD OPTION => VALUE

Returns a new Thread::Barrier object with a release threshold of C<THRESHOLD>.
C<THRESHOLD> must be an integer greater than or equal to 1.

Optional parameters may be specified in a hash-like fashion.  At present
the supported options are:

=over 8

=item Action => CODEref

A code reference to be run by one thread just before barrier release.
Precisely which thread runs the action is unspecified.  The default is
C<undef>, meaning no action will be taken.

=item RaiseError => boolean

A boolean parameter controlling whether broken barriers raise an exception
or simply return C<undef> as described under L</"BROKENNESS">.  The
default is true, meaning broken barriers raise exceptions.

=back

=item set_threshold COUNT

C<set_threshold> specifies the threshold count for the barrier, which must
be zero or a positive integer.  (Note that a threshold of zero or one is
rather a degenerate case barrier.)  If the new value of C<COUNT> is less
than or equal to the number of threads blocked on the barrier, the barrier
is released.

Returns true if the barrier is released because of the adjustment, false
otherwise.

=item wait

=item wait TIMEOUT

C<wait> blocks the calling thread until the number of threads blocking on the
barrier meets the threshold.  When the blocked threads are released, the
barrier is reset to its initial state and ready for re-use.

The calling thread may optionally block for up to TIMEOUT seconds.  If any
blocked thread times out, the barrier is broken as described under
L</"BROKENNESS">, below.

This method returns a true value to one of the released threads, and false to
all others.  Precisely which thread receives the true value is
unspecified.

=item threshold

Returns the current threshold.

=item count

Returns the instantaneous count of threads blocking on the barrier.

=back

=head1 BROKENNESS

In this context, brokenness is a feature.  Thread::Barrier objects may break
for one of two reasons:  either because the barrier L</Action> C<die()d>, or
because a call to L</wait> timed out.  In either case, the program logic behind
the barrier has been violated, and it is usually very difficult to
re-synchronize the program once this has happened.

When a Thread::Barrier object is broken, pending and subsequent calls to
L</wait> immediately raise an exception or return C<undef> depending on the
value of L</RaiseError>.

=head1 SEE ALSO

L<perlthrtut>.

=head1 AUTHORS

Mark Rogaski, E<lt>mrogaski@cpan.orgE<gt>
Mike Pomraning, E<lt>mjp@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2003, 2005, 2007 by Mark Rogaski, mrogaski@cpan.org; 2013 by
Mark Rogaski and Mike Pomraning, mjp@cpan.org;  all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the README file distributed with
Perl for further details.


=cut

