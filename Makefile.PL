use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  VERSION   => '0.4',
  PREREQ_PM => {'Mojolicious' => '5.04'},
  test      => {TESTS => 't/*.t'}
);
