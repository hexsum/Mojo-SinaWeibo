package Mojo::SinaWeibo;
use strict;
use utf8;
use Mojo::URL;
use Mojo::Util qw(sha1_sum b64_encode url_escape url_unescape decode encode);
# 获取图片验证码
#   api             :可选，默认值 'http://login.sina.com.cn/sso/login.php';
#   pwencode        :可选，登录加密算法类型，默认rsa
#   servertime      :必选
#   nonce           :必选
#   exectime        :必选
#   rsakv           :必选
#   pubkey          :必选
#   need_pin        :必选
#   verifycode      :可选，验证码
#   pcid            :可选，验证码id
#   returntype      :可选，TEXT|META
sub _login {
    my $self = shift;
    $self->info("正在登录...");
    my %opt  = @_;
    my $api = $opt{api} || 'http://login.sina.com.cn/sso/login.php';
    my $pwencode = $opt{pwencode} || "rsa";

    my $sp;

    if($pwencode eq "rsa"){
        $self->debug("登录使用rsa加密算法");
        my $has_crypt_rsa = 0;
        my $has_crypt_openssl_rsa = 0;
        eval{
            require Crypt::RSA::ES::PKCS1v15;
            require Crypt::RSA::Key::Public;
        };
        if( not $@){$has_crypt_rsa = 1}
        else{
            eval{
                require Crypt::OpenSSL::RSA;
                require Crypt::OpenSSL::Bignum;
            };
            if(not $@){$has_crypt_openssl_rsa = 1}
            else{
                $self->error("必须安装 Crypt::RSA 或者 Crypt::OpenSSL::RSA 模块来支持登录加密算法");
                $self->stop;
            }
        }

        if($has_crypt_rsa){
            my $public = Crypt::RSA::Key::Public->new;
            $public->n("0x" . $opt{pubkey});
            $public->e("0x10001");
            my $rsa = Crypt::RSA::ES::PKCS1v15->new;
            $sp = 
                lc join "",unpack "H*",
                $rsa->encrypt(
                    Key=>$public,
                    Message=>$opt{servertime} . "\t" . $opt{nonce} . "\n" . $opt{pwd}
             );
        }
        elsif($has_crypt_openssl_rsa){
            my $n = Crypt::OpenSSL::Bignum->new_from_hex("0x" . $opt{pubkey});
            my $e = Crypt::OpenSSL::Bignum->new_from_hex("0x10001");
            my $rsa = Crypt::OpenSSL::RSA->new_key_from_parameters($n,$e);
            $rsa->use_pkcs1_padding();
            $sp = lc join "",unpack "H*", $rsa->encrypt($opt{servertime} . "\t" . $opt{nonce} . "\n" . $opt{pwd});
        } 
        else{
            $self->error("登录失败: 加密算法计算失败");
            $self->stop();
        }
    }
    elsif($pwencode eq "wsse"){
        $self->debug("登录使用wsse加密算法");
        $sp = sha1_sum( "" . sha1_sum(sha1_sum($self->pwd)) . $opt{servertime} . $opt{nonce} );
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
        pwencode    => ($pwencode eq "rsa"?"rsa2":"wsse"),
        encoding    => "UTF-8",
        prelt       => $opt{exectime},
        url         => 'http://weibo.com/ajaxlogin.php?framelogin=1&callback=parent.sinaSSOController.feedBackUrlCallBack',
        returntype  => $opt{returntype} || "META",
        servertime  => $opt{servertime},
        nonce       => $opt{nonce},
        rsakv       => $opt{rsakv},
        su          => b64_encode(url_escape($opt{account}),""),
        sp          => $sp,
    };

    if($opt{need_pin}){
        $post->{door}   = $opt{verifycode};
        $post->{pcid}   = $opt{pcid};
        $post->{sr}     = "1366*768";
    }

    my $data = $self->http_post($api . '?client=ssologin.js%28v1.4.18%29',form=>$post);
    return if not defined $data;
    my ($retcode,$reason,$feedbackurl,$json);
    if($post->{returntype} eq "META"){
        return unless $data =~/location.replace\(['"](.*?)['"]\)/;
        $feedbackurl = Mojo::URL->new($1);
        $feedbackurl->query->charset("gbk");
        $retcode = $feedbackurl->query->param("retcode");
        $reason = $feedbackurl->query->param("reason") if defined $feedbackurl->query->param("reason");
    }
    elsif($post->{returntype} eq "TEXT"){
        $json = $self->decode_json($data);
        $retcode = $json->{retcode};
        $reason = $json->{reason} if exists $json->{reason};
    }


    if($retcode == 0){
        if($post->{returntype} eq "TEXT"){
            return {
                retcode => 0,
                ticket  => $json->{ticket},
                id     => $json->{uid},
                home    => "http://weibo.com/u/$json->{uid}/home",
                nick    => $json->{nick},
            };
        }
        elsif($post->{returntype} eq "META"){
            my($ticket,$id,$home,$nick); 
            if($data=~/sinaSSOController\.setCrossDomainUrlList\((.*?)\)/){
                my $json = $self->decode_json($1);
                my $i=0;
                $self->debug("处理跨域访问域名列表...");
                for  (@{ $json->{arrURL} }){
                    my $url = Mojo::URL->new($_);
                    $url->query->merge(
                        callback    =>  "sinaSSOController.doCrossDomainCallBack",
                        scriptId    =>  "ssoscript$i",
                        client      =>  'ssologin.js(v1.4.18)',
                        _           =>  time,
                    );
                    $self->http_get($url->to_string);
                    $i++;
                } 
            }   
            my $data = $self->http_get($feedbackurl->to_string);
            return if not defined $data;
            return if  $data !~ /parent\.sinaSSOController\.feedBackUrlCallBack\((.*?)\)/;
            $self->debug("获取登录回调参数...");
            my $json = $self->decode_json($1);
            return if not defined $json;
            return if not $json->{result};
            $ticket = $feedbackurl->query->param("ticket");
            $id = $json->{userinfo}{uniqueid};
            $home = defined $json->{redirect}?$json->{redirect}:"http://weibo.com/" . $json->{userinfo}{userdomain};
            $self->debug("进行首页跳转...");
            my $data = $self->http_get($home,{ua_debug_res_body=>0});
            return if not defined $data;
            my %config = $data =~ /\$CONFIG\[(?:'|")([^'"]+)(?:'|")\]\s*=(?:'|")([^'"]+)(?:'|")\s*;/g;
            $self->login_state("success");
            return {retcode=>0,ticket=>$ticket,id=>$id,home=>$home,nick=>$config{nick}};
        }
    }
    elsif($retcode ==4049){
        return {retcode=>1,}
    }
    else{
        $self->error($reason?"登录失败: $retcode($reason)":"登录失败: $retcode"); 
        return;
    }
}
1;
