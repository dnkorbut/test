use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'engine.pl',
  VERSION      => '1.0',
  AUTHOR       => 'Parkcode <dnkorbut@gmail.com>',
  EXE_FILES    => ['engine.pl'],
  PREREQ_PM    => {'JSON' => '0.1'}
);
