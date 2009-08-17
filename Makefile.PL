use inc::Module::Install;
name 'Net-WeatherNews-QuakeWarning';
all_from 'lib/Net/WeatherNews/QuakeWarning.pm';

build_requires 'Test::More';
use_test_base;
auto_include_deps;
author_tests('xt');
auto_set_repository;
WriteAll;
