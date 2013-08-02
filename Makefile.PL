# Makefile.PL for Thread::Barrier

require 5.008;

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME		      => 'Thread::Barrier',
    VERSION_FROM 	=> 'Barrier.pm',
    ABSTRACT_FROM => 'Barrier.pm',
    AUTHOR        => 'Mike Pomraning <mjp@cpan.org>',
    PREREQ_PM     => {
                       'threads::shared' => 0,
                       'Carp'            => 0,
                       'Test::More'      => 0,
                     },
    ((ExtUtils::MakeMaker->VERSION() gt '6.30') ?
       (LICENSE   => 'perl')           : ()),
);

