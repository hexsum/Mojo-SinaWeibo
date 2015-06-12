use 5.010001;;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Mojo::SinaWeibo',
    VERSION_FROM      => 'lib/Mojo/SinaWeibo.pm', # finds $VERSION
    DISTNAME            => 'Mojo-SinaWeibo',
    LICENSE             => "perl",
    PREREQ_PM         => {
        "Mojolicious"           => '6.11',
        "IO::Socket::SSL"       => '1.94',
        "Encode::Locale"        => 0,
    }, # e.g., Module::Name => 1.1
    dist              => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Mojo-SinaWeibo-* MANIFEST' },
    META_MERGE => {
        resources => {     
            repository=>{
                type    => 'git',
                url     => 'git://github.com/sjdy521/Mojo-SinaWeibo.git',
                web     =>  'https://github.com/sjdy521/Mojo-SinaWeibo',
            },
        },
    },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (
       ABSTRACT       => 'A SinaWeibo XiaoIce SDK and API',
       AUTHOR         => 'sjdy521 <sjdy521@163.com>') : ()),
);
