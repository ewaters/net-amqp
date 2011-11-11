use Module::Build;

my $build = Module::Build->new(
    module_name => 'Net::AMQP',
    license => 'perl',
    build_requires => {
        'File::Temp' => 0.19,
        'Test::More' => 0.88,
        'Test::Deep' => 0,
    },
    requires => {
        'Params::Validate' => 0,
        'Class::Accessor' => 0,
        'Class::Data::Inheritable' => 0,
        'XML::LibXML' => 0,
    },
    sign => 1,
    create_makefile_pl => 'passthrough',
    create_readme => 1,
);

$build->create_build_script;
