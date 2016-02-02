Mojo-SinaWeibo v1.6 [![Build Status](https://travis-ci.org/sjdy521/Mojo-SinaWeibo.svg?branch=master)](https://travis-ci.org/sjdy521/Mojo-SinaWeibo)
========================
使用Perl语言编写的新浪微博客户端SDK，基于Mojolicious，要求Perl版本不低于5.10
实现新浪微博登录和私信功能，能够通过微博私信和微软小冰进行问答
其他微博功能敬请期待

###使用说明

   1）准备一个可以和小冰正常私信往来的微博帐号
   2）推荐微博帐号进行手机绑定，并设置常用登录地点免验证码登录（可以避免输入验证码带来的麻烦）
   3）通过SDK提供的函数接口或者使用内置的API server来和小冰互动

###SDK示例代码

    use Mojo::SinaWeibo;
    use Data::Dumper;
    my $m = Mojo::SinaWeibo->new(
         ua_debug=>0,
         log_level=>"info",
         user=>'xxxxx',#微博帐号
         pwd=>'xxxx',  #帐号密码
    );
    $m->ask_xiaoice("你是谁",sub{print Dumper \@_}); #中文使用UTF8编码
    $m->run(enable_api_server=>1,host=>"127.0.0.1",port=>8000);

###API调用示例

    > GET /openxiaoice/ask?q=hello HTTP/1.1  #中文请使用UTF编码进行urlencode
    > User-Agent: curl/7.15.5 (x86_64-redhat-linux-gnu) libcurl/7.15.5
    > Host: 127.0.0.1:8000
    > Accept: */*
    > 
    < HTTP/1.1 200 OK
    < Server: Mojolicious (Perl)
    < Content-Type: application/json;charset=UTF-8
    < Connection: keep-alive
    < Date: Fri, 12 Jun 2015 08:01:08 GMT
    < Content-Length: 52
    Connection #0 to host 127.0.0.1 left intact
    * Closing connection #0
    {"code":1,"answer":"hello.这么巧你也失眠了"}

###运行日志

    [15/06/12 16:00:47] [info] 准备登录微博帐号[ xxxx ]
    [15/06/12 16:00:47] [info] 正在登录...
    [15/06/12 16:00:49] [info] 登录成功
    [15/06/12 16:00:49] [info] http server available at 0.0.0.0:8000
    [15/06/12 16:00:49] [私信消息] 我->小冰 : 你是谁
    [15/06/12 16:00:51] [私信消息] 我->小冰 : howareyou
    [15/06/12 16:00:51] [私信消息] 小冰 : 我是小灰啊，陪在你身边的知心人
    [15/06/12 16:00:52] [私信消息] 小冰 : 我爸爸给我买了个表
    [15/06/12 16:01:00] [私信消息] 我->小冰 : hello
    [15/06/12 16:01:08] [私信消息] 小冰 : hello.这么巧你也失眠了

###安装步骤

推荐使用[cpanm](https://metacpan.org/pod/distribution/App-cpanminus/bin/cpanm)在线安装[Mojo::SinaWeibo](https://metacpan.org/pod/Mojo::SinaWeibo)模块

1. *安装cpanm工具*

    方法a： 通过cpan安装cpanm

        $ cpan -i App::cpanminus

    方法b： 直接在线安装cpanm

        $ curl -L http://cpanmin.us | perl - App::cpanminus

2. *使用cpanm在线安装 Mojo::SinaWeibo 模块*

        $ cpanm -v Mojo::SinaWeibo

3. *安装失败可能有帮助的解决方法*

    如果你运气不佳，通过cpanm没有一次性安装成功，这里提供了一些可能有用的信息

    在安装 Mojo::SinaWeibo 的过程中，cpan或者cpanm会帮助我们自动安装很多其他的依赖模块

    在众多的依赖模块中，安装经常容易出现问题的主要是 IO::Socket::SSL

    IO::Socket::SSL 主要提供了 https 支持，在安装过程中可能会涉及到SSL相关库的编译

    对于 Linux 用户，通常采用的是编译安装的方式，系统缺少编译安装必要的环境，则会导致编译失败

    对于 Windows 用户，由于不具备良好的编译安装环境，推荐采用一些已经打包比较全面的Perl运行环境

    例如比较流行的 strawberryperl 或者 activeperl 的最新版本都默认包含 Mojo::SinaWeibo 的核心依赖模块

    RedHat/Centos:

        $ yum install -y openssl-devel

    Ubuntu:

        $ sudo apt-get install libssl-dev

    Window:

    这里以 strawberryperl 为例

    安装 [Strawberry Perl](http://strawberryperl.com/)，这是一个已经包含 Mojo::SinaWeibo 所需核心依赖的较全面的Windows Perl运行环境

    [32位系统安装包](http://strawberryperl.com/download/5.22.0.1/strawberry-perl-5.22.0.1-32bit.msi)

    [64位系统安装包](http://strawberryperl.com/download/5.22.0.1/strawberry-perl-5.22.0.1-64bit.msi)

    或者自己到 [Strawberry Perl官网](http://strawberryperl.com/) 下载适合自己的最新版本

    安装前最好先卸载系统中已经安装的其他Perl版本以免互相影响

    搞定了编译和运行环境之后，再重新回到 步骤2 安装 Mojo::SinaWeibo 即可

###核心依赖模块

* Mojolicious
* Crypt::RSA
* Encode::Locale

###相关文档

* [更新日志](https://github.com/sjdy521/Mojo-SinaWeibo/blob/master/Changes)
* [开发文档](https://metacpan.org/pod/Mojo::SinaWeibo)

###官方交流

* [QQ群](http://jq.qq.com/?_wv=1027&k=kjVJzo)
* [IRC](http://irc.perfi.wang/?channel=#Mojo-Webqq)

###版本更新记录

请参见 Changes 文件

###COPYRIGHT 和 LICENCE

Copyright (C) 2014 by sjdy521

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.
