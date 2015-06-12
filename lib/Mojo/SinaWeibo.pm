package Mojo::SinaWeibo;
$Mojo::SinaWeibo::VERSION = "1.1";
use Mojo::Base 'Mojo::EventEmitter';
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Util qw(b64_encode dumper sha1_sum url_escape url_unescape encode decode);
use Mojo::URL;
use Crypt::RSA::ES::PKCS1v15;
use Crypt::RSA::Key::Public;
use POSIX;
use Carp;
use Time::HiRes qw();
use List::Util qw(first);
use Mojo::IOLoop;
use File::Temp qw/tempfile/;
use Encode::Locale ;
use Fcntl ':flock';

has 'user';
has 'pwd';
has ua_debug                => 0;
has log_level               => 'info';     #debug|info|warn|error|fatal
has log_path                => undef;

has max_timeout_count       => 3;
has timeout                 => 8;
has timeout_count           => 0;

has log => sub{
    require Mojo::Log;
    no warnings 'redefine';
    *Mojo::Log::append = sub{
        my ($self, $msg) = @_;
        return unless my $handle = $self->handle;
        flock $handle, LOCK_EX;
        $handle->print(encode("console_out", $msg)) or croak "Can't write to log: $!";
        flock $handle, LOCK_UN;
    };
    Mojo::Log->new(path=>$_[0]->log_path,level=>$_[0]->log_level,format=>sub{
        my ($time, $level, @lines) = @_;
        my $title="";
        if(ref $lines[0] eq "HASH"){
            my $opt = shift @lines; 
            $time = $opt->{"time"} if defined $opt->{"time"};
            $title = (defined $opt->{"title"})?$opt->{title} . " ":"";
            $level  = $opt->{level} if defined $opt->{"level"};
        }
        #$level .= " " if ($level eq "info" or $level eq "warn");
        @lines = split /\n/,join "",@lines;
        my $return = "";
        $time = POSIX::strftime('[%y/%m/%d %H:%M:%S]',localtime($time));
        for(@lines){
            $return .=
                $time
            .   " " 
            .   "[$level]" 
            . " " 
            . $title 
            . $_ 
            . "\n";
        }
        return $return;
    });
};
has ua                      => sub {
    local $ENV{MOJO_USERAGENT_DEBUG} = 0;
    require Mojo::UserAgent;
    Mojo::UserAgent->new(
        request_timeout    => 30,
        inactivity_timeout => 30,
        max_redirects      => 7,
        transactor => Mojo::UserAgent::Transactor->new( 
            name =>  'Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062'
        ),
    );
};

has 'nick';
has login_type  => "rsa";#wsse
has api_form => "HTML";#HTML|JSON
has login_state => "invalid";
has 'need_pin' => 0;
has rsa => sub {Crypt::RSA::ES::PKCS1v15->new};
has 'servertime';
has 'pcid';
has 'pubkey';
has 'nonce';
has 'rsakv';
has 'exectime';
has 'verifycode';
has 'uid';
has 'home';
has 'showpin';
has 'ticket';
has 'im_msg_id' => 0;
has 'im_ack' => -1;
has 'im';
has 'im_clientid';
has 'im_channel';
has 'im_server';
has 'im_connect_interval' => 0;
has 'im_xiaoice_uid' => 5175429989;
has 'im_client_lag_data' => sub{[]};
has 'im_server_lag_data' => sub{[]};
has 'im_ready' => 0;
has im_user => sub {[]};
has 'im_api_server';

sub search_im_user{
    my $s = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    if(wantarray){
        return grep {my $f = $_;(first {$p{$_} ne $f->{$_}} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$s->im_user};
    }
    else{
        return first {my $f = $_;(first {$p{$_} ne $f->{$_}} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$s->im_user};
    }
}
sub add_im_user{
    my $s = shift;
    my $user = shift;
    $s->die("不支持的数据类型") if ref $user ne "HASH";
    $s->die("不支持的数据类型") if not exists $user->{uid} ;
    $s->die("不支持的数据类型") if not exists $user->{nick} ;
    my $nocheck = shift;
    if(@{$s->im_user}  == 0){
        push @{$s->im_user},$user;
        return $s;
    }
    if($nocheck){
        push @{$s->im_user},$user;
        return $s;
    }
    my $u = $s->search_im_user(uid => $user->{uid});
    if(defined $u){
        $u = $user;
    }
    else{#new user
        push @{$s->im_user},$user;
    }
    return $s;
}

sub auth {
    my $s = shift;
    return $s if $s->login_state eq "success";
    $s->prelogin();
    $s->login();
    if($s->login_state eq "success"){
        return $s
    }
    $s->fatal("授权失败，程序退出");
    exit;
}
sub login {
    my $s = shift;
    $s->info("正在登录...");
    my $api = 'http://login.sina.com.cn/sso/login.php';
    my $sp = "";
    if($s->login_type eq "rsa"){
        $s->debug("登录使用rsa加密算法");
        my $public = Crypt::RSA::Key::Public->new;
        $public->n("0x" . $s->pubkey);
        $public->e("0x10001");
        $sp = 
            lc join "",unpack "H*",
            $s->rsa->encrypt(
                Key=>$public,
                Message=>$s->servertime . "\t" . $s->nonce . "\n" . $s->pwd
            );
    }
    elsif($s->login_type eq "wsse"){
        $s->debug("登录使用wsse加密算法");
        $sp = sha1_sum( "" . sha1_sum(sha1_sum($s->pwd)) . $s->servertime . $s->nonce );
    }
    my $post = {
        entry       => "weibo",
        gateway     => 1,
        from        => "",
        savestate   => 7,
        useticket   => 1,
        pagerefer   => '',
        vsnf        => 1,
        service     => "miniblog",
        pwencode    => ($s->login_type eq "rsa"?"rsa2":"wsse"),
        encoding    => "UTF-8",
        prelt       => $s->exectime,
        url         => 'http://weibo.com/ajaxlogin.php?framelogin=1&callback=parent.sinaSSOController.feedBackUrlCallBack',
        returntype  => ($s->api_form eq "JSON"?"TEXT":"META"),
        servertime  => $s->servertime,
        nonce       => $s->nonce,
        rsakv       => $s->rsakv,
        su          => b64_encode(url_escape($s->user),""),
        sp          => $sp,
    };

    $post->{door} = $s->verifycode if $s->need_pin;
    $post->{pcid} = $s->pcid if $s->need_pin;
    $post->{sr} = "1366*768" if $s->need_pin;

    my $tx = $s->ua->post($api . '?client=ssologin.js%28v1.4.18%29' ,form=>$post);
    if($s->ua_debug){
        print $tx->req->to_string,"\n";
        print $tx->res->to_string,"\n";
    }
    return unless $tx->success;
    my ($retcode,$reason,$feedbackurl,$json);
    if($post->{returntype} eq "META"){
        return unless $tx->res->body =~/location.replace\(['"](.*?)['"]\)/;
        $feedbackurl = Mojo::URL->new($1);
        $retcode = $feedbackurl->query->param("retcode");
        $reason = decode("gb2312",url_unescape($feedbackurl->query->param("reason"))) if defined $feedbackurl->query->param("reason");
    }
    elsif($post->{returntype} eq "TEXT"){
        $json = decode_json($tx->res->body);
        $retcode = $json->{retcode};
        $reason = $json->{reason} if exists $json->{reason};
    }
    if($retcode == 0){
        if($post->{returntype} eq "TEXT"){
          $s->ticket($json->{ticket})
            ->uid($json->{uid})
            ->home("http://weibo.com/u/$json->{uid}/home")
            ->nick($json->{nick})
            ->login_state("success");
            $s->info("登录成功");
        }
        elsif($post->{returntype} eq "META"){   
            $s->ticket($feedbackurl->query->param("ticket"));
            if($tx->res->body=~/sinaSSOController\.setCrossDomainUrlList\((.*?)\)/){
                my $json = decode_json($1);
                my $i=0;
                $s->debug("处理跨域访问域名列表...");
                for  (@{ $json->{arrURL} }){
                    my $url = Mojo::URL->new($_);
                    $url->query->merge(
                        callback    =>  "sinaSSOController.doCrossDomainCallBack",
                        scriptId    =>  "ssoscript$i",
                        client      =>  'ssologin.js(v1.4.18)',
                        _           =>  $s->time(),
                    );
                    my $tx = $s->ua->get($url->to_string);
                    if($s->ua_debug){
                        print $tx->req->to_string,"\n";
                        print $tx->res->to_string,"\n";
                    }
                    $i++;
                } 
            }   
            my $tx = $s->ua->get($feedbackurl->to_string);
            if($s->ua_debug){
                print $tx->req->to_string,"\n";
                print $tx->res->to_string,"\n";
            }
            return unless $tx->success;
            return unless $tx->res->body =~/parent\.sinaSSOController\.feedBackUrlCallBack\((.*?)\)/;
            $s->debug("获取登录回调参数...");
            my $json = decode_json($1);
            return unless $json->{result};
            $s->uid($json->{userinfo}{uniqueid})->home("http://weibo.com/u/$json->{userinfo}{uniqueid}/home");
            if(defined $json->{redirect}){
                $s->debug("进行首页跳转...");
                my $tx = $s->ua->get($json->{redirect}) ;
                return unless $tx->success;
                $s->login_state("success");
                $s->info("登录成功");
            }
        }
    }
    elsif($retcode ==4049){
        $s->get_pin() && $s->login();
    }
    else{
        $s->error($reason?"登录失败: $retcode($reason)":"登录失败: $retcode"); 
        return;
    }
}

sub get_im_info{
    my $s = shift;
    return +{channel=>$s->im_channel,server=>$s->im_server} if (defined $s->im_channel and $s->im_server);
    my $api = "http://nas.im.api.weibo.com/im/webim.jsp";
    my $callback = "IM_" . $s->time();
    my $query_string = {
        uid             => $s->uid,
        returntype      => "json",
        v               => "1.1",
        callback        => $callback,
        __rnd           => $s->time(),
    };
    $s->debug("获取私信服务器地址...");
    my $tx = $s->ua->get($api,{Referer=>$s->home},form=>$query_string);
    if($s->ua_debug){
        print $tx->req->to_string,"\n";
        print $tx->res->to_string,"\n";
    }
    return unless $tx->success;
    return unless $tx->res->body=~/\Q$callback\E\((.*?)\)/;
    my $json = decode_json($1);
    $json->{server} =~s#^http#ws#;
    $json->{server} =~s#/$##;
    $s->debug("私信服务器地址[ " .  $json->{server} . $json->{channel} . " ]");
    $json->{server} .= "/im";
    $s->im_server($json->{server})->im_channel($json->{channel});
    return {channel=>$json->{channel},server=>$json->{server}};
}


sub get_pin{
    my $s = shift;
    $s->info("正在获取验证码图片...");
    my $api = 'http://login.sina.com.cn/cgi/pin.php';
    my $query_string = {
        r   => POSIX::floor(rand() * (10**8)), 
        s   => 0,
        p   => $s->pcid,
    };
    my $tx = $s->ua->get($api,form=>$query_string);
    if($s->ua_debug){
        print $tx->req->to_string,"\n";
        print $tx->res->headers->to_string,"\n";
    }
    return unless $tx->success;
    my ($fh, $filename) = tempfile("sinaweibo_img_verfiy_XXXX",SUFFIX =>".png",TMPDIR => 1);
    binmode $fh;
    print $fh $tx->res->body;
    close $fh;
    my $filename_for_console = decode("locale_fs",$filename);
    my $info = $s->log->format->(CORE::time,"info","请输入图片验证码 [ $filename_for_console ]: "); 
    chomp $info;
    $s->log->append($info);
    my $input;
    chomp($input=<STDIN>);
    $s->verifycode($input)->need_pin(1);
    return 1;
}


sub prelogin{
    my $s = shift;
    $s->info("准备登录微博帐号[ ".$s->user." ]");
    my $api = 'http://login.sina.com.cn/sso/prelogin.php';
    my $query_string = {
        entry   => 'weibo',
        client  => 'ssologin.js(v1.4.18)',
        callback => 'sinaSSOController.preloginCallBack',
        su      => 'TGVuZGZhdGluZyU0MHNpbmEuY29t',
        rsakt   => 'mod',
        checkpin => '1',
        _        => $s->time(),
    };
    my $tx = $s->ua->get($api,form=>$query_string);
    if($s->ua_debug){
        print $tx->req->to_string,"\n";
        print $tx->res->to_string,"\n";
    }
    return unless $tx->success;
    return unless $tx->res->body =~ /^sinaSSOController\.preloginCallBack\((.*)\)$/;
    my $json = decode_json($1); 
    return  if $json->{retcode}!=0;
    for (qw(servertime pcid pubkey nonce rsakv exectime showpin)){
        $s->$_($json->{$_}) if exists $json->{$_};
    }
}

sub gen_im_msg_id {
    my $s = shift;
    my $last_id = $s->im_msg_id;
    $s->im_msg_id(++$last_id);
    return $last_id;
}
sub gen_im_ack{
    my $s = shift;
    my $last_ack = $s->im_ack;
    if($last_ack == -1){
        $s->im_ack(0);
        return $last_ack;
    }
    else{
        $s->im_ack(++$last_ack);
        return $last_ack;
    }
}

sub time{
    my $s = shift;
    return int(Time::HiRes::time * 1000);
}
sub gmtime_string {
    my $s = shift;
    my $time = shift;
    $time = CORE::time unless defined $time;
    my @DoW = qw(Sun Mon Tue Wed Thu Fri Sat);
    my @MoY = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my %MoY;
    @MoY{@MoY} = (1..12);
    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = CORE::gmtime($time);
    sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT",
            $DoW[$wday],
            $mday, $MoY[$mon], $year+1900,
            $hour, $min, $sec);
}

sub gen_im_msg{
    my $s = shift;
    my $type = shift;
    my $msg = {};
    if($type eq "handshake"){
        $msg = 
            {
                version         =>  "1.0",
                minimumVersion  =>  "0.9",
                channel         =>  "/meta/handshake",
                supportedConnectionTypes=> ["websocket",],#"callback-polling"],
                advice          => {timeout=>60000,interval=>0},
                id              => $s->gen_im_msg_id,
                ext             => {ack => Mojo::JSON->true,timesync=>{tc=>$s->time,l=>0,o=>0}},
                timestamp       => $s->gmtime_string,
            };
    }
    elsif($type eq "connect"){
        $msg = 
            {
                channel         =>  "/meta/connect",
                connectionType  =>  "websocket",
                clientId        => $s->im_clientid,
                id              => $s->gen_im_msg_id(),
                ext             => {ack => $s->gen_im_ack(),timesync=>{tc=>$s->time,l=>0,o=>0}},
                timestamp       => $s->gmtime_string,
            };
        $msg->{advice} = {timeout=>0,} if $msg->{ext}{ack} == -1;
    }
    elsif($type eq "subscribe"){
        my %p = @_;
        $msg = 
            {
                channel         =>  "/meta/subscribe",
                subscription    => $p{channel},
                id              => $s->gen_im_msg_id,
                clientId        => $s->im_clientid,
                ext             => {timesync=>{tc=>$s->time,l=>0,o=>0}},
                timestamp       => $s->gmtime_string,
            };
    }
    elsif($type eq "cmd"){
        my %p = @_;
        my $data ={};
        $data = {cmd=>"recents"} if $p{cmd} eq "recents";
        $data = {cmd=>"usersetting",subcmd=>"get",seq=>"get"} if $p{cmd} eq "usersetting";
        if($p{cmd} eq "msg"){
            $data = {cmd=>"msg",uid=>$p{uid},msg=>$p{msg}} ;
        }
        $msg = 
            {
                channel         =>  "/im/req",
                data            => $data,
                id              => $s->gen_im_msg_id,
                clientId        => $s->im_clientid,
                timestamp       => $s->gmtime_string,
            };
    }
    return $msg;
}
sub parse_im_msg{
    my $s = shift;
    my $msg = shift;
    print encode_json($msg),"\n" if $s->ua_debug;
    for my $m(@{$msg}){
        if($m->{channel} eq '/meta/handshake'){
            $s->debug("收到服务器握手消息");
            return unless first {$_ eq "websocket"} @{$m->{supportedConnectionTypes}};
            return unless $m->{successful};
            $s->debug("服务器握手成功");
            $s->im_clientid($m->{clientId});
            $s->im_send($s->gen_im_msg("subscribe",channel=>$s->im_channel));
            $s->im_send($s->gen_im_msg("connect"));
        }
        elsif($m->{channel} eq "/meta/connect"){
            $s->debug("收到服务器心跳响应 ack: ".$m->{ext}{ack});
            return unless $m->{successful};
            if(exists $m->{advice} and exists $m->{advice}{interval}){
                $s->im_connect_interval($m->{advice}{interval}/1000);
            }
            $s->timer( $s->im_connect_interval,sub{
                my $msg = $s->gen_im_msg("connect");
                if(exists $m->{ext}{timesync}){
                    my $i = $s->time;
                    my $k = ($i -$m->{ext}{timesync}{tc} - $m->{ext}{timesync}{p})/2;
                    my $l = $m->{ext}{timesync}{ts} - $m->{ext}{timesync}{ts} - $k;
                    push @{$s->im_client_lag_data},$k;
                    push @{$s->im_server_lag_data},$l;
                    if(10<@{$s->im_server_lag_data}){
                        shift @{$s->im_server_lag_data};shift @{$s->im_client_lag_data};
                    }
                    my $n=0;
                    my $o=0;
                    for(my $p=0;$p<@{$s->im_server_lag_data};$p++){
                        $n+=$s->im_client_lag_data->[$p];
                        $o+=$s->im_server_lag_data->[$p];
                    }

                    my $g = int($n/@{$s->im_server_lag_data});my $h=int($o/@{$s->im_server_lag_data});
                    $msg->{ext}{timesync}{l} = $g;
                    $msg->{ext}{timesync}{o} = $h;
                }
                $s->im_send($msg);
            });
        }
        elsif($m->{channel} eq "/meta/subscribe"){
            return unless $m->{successful};
            $s->debug("收到服务器订阅响应消息");
            $s->im_send($s->gen_im_msg("cmd",cmd=>"usersetting"));
            $s->im_send($s->gen_im_msg("cmd",cmd=>"recents"));
        }
        elsif($m->{channel} eq "/im/req"){
            next unless $m->{successful};
        }
        elsif($m->{channel} eq $s->im_channel){
            return unless exists $m->{data}{type};
            if($m->{data}{type} eq "recents"){
                $s->im_user([ map {{uid=>$_->[0],nick=>$_->[1]}} @{$m->{data}{recents}} ]);
                $s->im_ready(1);
                $s->debug("私信服务器状态准备就绪");
                $s->emit("im_ready");
            }            

            elsif( $m->{data}{type} eq "msg"){
                for(@{$m->{data}{items}}){
                    my($uid,$msg,$time) = @$_[0..2];
                    my $u = $s->search_im_user(uid=>$uid);
                    my $nick = defined $u?$u->{nick}:"未知昵称";
                    $s->emit("receive_message",{uid=>$uid,nick=>$nick,content=>$msg,'time'=>int($time/1000)},{is_success=>1,code=>200,msg=>"正常响应"});
                    $s->emit_one("answer_message",{uid=>$uid,nick=>$nick,content=>$msg,'time'=>int($time/1000)},{is_success=>1,code=>200,msg=>"正常响应"});
                } 
            }
        
            elsif($m->{data}{type} eq "synchroniz" ){
                return unless exists $m->{data}{syncData};
                my $syncdata = decode_json(encode("utf8",$m->{data}{syncData}));
                return unless exists $syncdata->{msg};
                return unless exists $syncdata->{uid};
                my $time = exists $syncdata->{'time'}?int($syncdata->{'time'}/1000):CORE::time;
                my($uid,$msg) = ($syncdata->{uid}, $syncdata->{msg}); 
                my $u = $s->search_im_user(uid=>$uid);
                my $nick = defined $u?$u->{nick}:"未知昵称"; 
                $s->emit("send_message",{uid=>$uid,nick=>$nick,content=>$msg,'time'=>$time});
            }
        }
    }
    
}

sub im_init{
    my $s = shift;
    return if $s->im_ready;
    $s->im_msg_id(0)
      ->im_ack(-1)
      ->im_ready(0)
      ->im(undef)
      ->im_clientid(undef)
      ->im_connect_interval(0);
    my $im_info = $s->get_im_info();
    return unless defined $im_info;
    $s->ua->websocket($im_info->{server},sub{
        my ($ua, $tx) = @_;
        $s->error("Websocket服务器连接失败") and return unless $tx->is_websocket;
        $s->im($tx);
        $s->im->on(finish => sub {
            my ($tx, $code, $reason) = @_;
            $s->debug("WebSocket服务器关闭($code)");
            $s->im_ready(0);
            $s->debug("私信服务器状态失效");
        });
        $s->im->on(json=>sub{
            my ($tx, $msg) = @_;
            $s->parse_im_msg($msg);
        });
        if($s->im->is_established){
            $s->debug("Websocket服务器连接成功");
            $s->im_send($s->gen_im_msg("handshake"));
        }
    });
}

sub im_speek{
    my $s = shift;
    my $uid = shift;
    my $content = shift;
    my $callback = pop;
    $content = decode("utf8",$content) if defined $content;

    $s->auth() if $s->login_state eq "invalid";
    #timeout handle
    my $id;
    my $cb = {
        cb=>sub{
            Mojo::IOLoop->remove($id);
            $callback->(@_) if ref $callback eq "CODE"; 
        },
        status => 'wait',
        msg=>undef,
    };
    $id = $s->timer($s->timeout,sub{
        $cb->{status} = 'abort';
        $callback->(undef,{is_success=>0,code=>503,msg=>encode("utf8","响应超时")}) if ref $callback eq "CODE";
        $s->warn("消息响应超时");
        my $count = $s->timeout_count;
        $s->timeout_count(++$count);
        if($s->timeout_count >= $s->max_timeout_count){
            $s->im_ready(0);
            $s->login_state("invalid");
            $s->emit("invalid");
        }
    }); 
    #
    if($s->im_ready){
        my $msg = $s->gen_im_msg("cmd",cmd=>"msg",uid=>$uid,msg=>$content);
        $cb->{msg} = $msg;
        $s->im_send($msg,$cb);
        
    }
    else{
        $s->once(im_ready=>sub{
            my $s = shift;
            return if $cb->{status} eq "abort";
            my $msg = $s->gen_im_msg("cmd",cmd=>"msg",uid=>$uid,msg=>$content);
            $cb->{msg} = $msg;
            $s->im_send($msg,$cb);
        });
        $s->im_init();
    }

}

sub ask_xiaoice{
    my $s = shift;
    my $uid = $s->im_xiaoice_uid;
    my $content = shift;
    my $callback = pop;
    $s->im_speek($uid,$content,$callback);
}
sub im_send{
    my $s= shift;
    my $msg = shift;
    my $cb = shift;
    if($msg->{channel} eq "/im/req" and $msg->{data}{cmd} eq "msg" and ref $cb->{cb} eq "CODE"){
        $s->once(answer_message=>sub{
            my $s = shift;
            return if $cb->{status} eq "abort";
            my($msg,$status) = @_;
            if(defined $msg){
                $msg->{nick} = encode("utf8",$msg->{nick});
            }
            $status->{msg} = encode("utf8",$status->{msg});
            $cb->{cb}->($msg,$status);
        });
        #push @{$s->im_send_callback},$cb;
    };
    $s->im->send({json=>[$msg]},sub{
        print encode_json($msg),"\n" if $s->ua_debug;
        $s->debug("发送usersetting消息") if ($msg->{channel} eq "/im/req" and $msg->{data}{cmd} eq "usersetting");
        $s->debug("发送recents消息") if ($msg->{channel} eq "/im/req" and $msg->{data}{cmd} eq "recents");
        $s->debug("发送握手消息") if $msg->{channel} eq "/meta/handshake";
        $s->debug("发送心跳消息 ack: " . $msg->{ext}{ack}) if $msg->{channel} eq "/meta/connect";
        $s->debug("发送订阅消息") if $msg->{channel} eq "/meta/subscribe";
        if($msg->{channel} eq "/im/req" and $msg->{data}{cmd} eq "msg"){
            my $u=$s->search_im_user(uid=>$msg->{data}{uid});
            $s->emit("send_message"=>{
                uid=>$msg->{data}{uid},
                nick=>(defined $u?$u->{nick}:"未知昵称"),
                'time'=>CORE::time,
                content=>$msg->{data}{msg},
            }) 
        }
    });
}
sub run{
    my $s = shift;
    my %p = @_ if @_%2==0;
    $s->on(receive_message=>sub{
        my $s = shift;
        my $msg = shift;
        return if ref $msg ne "HASH";
        $s->info({level=>"私信消息",'time'=>$msg->{'time'},title=>"$msg->{nick} :"},$msg->{content}); 
    });
    $s->on(send_message=>sub{
        my $s = shift;
        my $msg = shift;
        return if ref $msg ne "HASH";
        $s->info({level=>"私信消息",'time'=>$msg->{'time'},title=>"我->$msg->{nick} :"},$msg->{content});
    });

    $s->on(invalid=>sub{
        my $s = shift;
        $s->warn("程序当前状态不可用，尝试重新授权");
        $s->auth();
    });

    if($p{enable_api_server} ==1){
        package Mojo::SinaWeibo::Openxiaoice;
        use Encode;
        use Mojolicious::Lite;
        any [qw(GET POST)] => '/openxiaoice/ask'         => sub{
            my $c = shift;
            my $q = $c->param("q");
            $c->render_later;
            $s->ask_xiaoice($q,sub{
                my($msg,$status) = @_;
                if($status->{is_success}){
                    $c->render(json=>{code=>1,answer=>$msg->{content}});      
                }
                else{
                    $c->render(json=>{code=>0,answer=>undef,reason=>decode("utf8",$status->{msg})});
                }
            });
        };
        package Mojo::SinaWeibo;          
        require Mojo::SinaWeibo::Server;
        my $data = [{host=>$p{host}||"0.0.0.0",port=>$p{port}||3000}] ;
        my $server = Mojo::SinaWeibo::Server->new(); 
        $s->im_api_server($server);
        $server->app($server->build_app("Mojo::SinaWeibo::Openxiaoice"));
        $server->app->secrets("hello world");
        $server->app->log($s->log);
        $server->listen($data) if ref $data eq "ARRAY" ;
        $server->start;
    }

    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

sub emit_one{
  my ($s, $name) = (shift, shift);
  if (my $e = $s->{events}{$name}) {
    my $cb = shift @$e;
    $s->$cb(@_);
  }
  return $s;
}
sub timer{
    my $s = shift;
    Mojo::IOLoop->timer(@_);
}
sub recurring{
    my $s = shift;
    Mojo::IOLoop->recurring(@_);
}

sub die{
    my $s = shift; 
    local $SIG{__DIE__} = sub{$s->log->fatal(@_);exit -1};
    Carp::confess(@_);
}
sub info{
    my $s = shift;
    $s->log->info(@_);
    $s;
}
sub warn{
    my $s = shift;
    $s->log->warn(@_);
    $s;
}
sub error{
    my $s = shift;
    $s->log->error(@_);
    $s;
}
sub fatal{
    my $s = shift;
    $s->log->fatal(@_);
    $s;
}
sub debug{
    my $s = shift;
    $s->log->debug(@_);
    $s;
}
1;
