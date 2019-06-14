package Mojo::SinaWeibo;
use strict;
use utf8;
# 登录准备
#   api     :可选，默认值 'http://login.sina.com.cn/sso/prelogin.php'
sub _prelogin {
    my $self = shift;
    $self->info("准备登录微博帐号[ ".$self->account." ]");
    my %opt = @_;
    my $api = $opt{api} || 'http://login.sina.com.cn/sso/prelogin.php';
    my $query_string = {
        entry   => 'weibo',
        client  => 'ssologin.js(v1.4.18)',
        callback => 'sinaSSOController.preloginCallBack',
        su      => 'TGVuZGZhdGluZyU0MHNpbmEuY29t',
        rsakt   => 'mod',
        checkpin => '1',
        _        => time,
    };
    my $data = $self->http_get($api,form=>$query_string);
    return if not defined $data;
    return if not $data=~/^sinaSSOController\.preloginCallBack\((.*)\)$/;
    my $json = $self->decode_json($1);
    return if not defined $json;
    #sinaSSOController.preloginCallBack({"retcode":0,"servertime":1468575447,"pcid":"xd-8f4119115bd1a2ff81ad6db78648a59765d3","nonce":"TF4MQB","pubkey":"EB2A38568661887FA180BDDB5CABD5F21C7BFD59C090CB2D245A87AC253062882729293E5506350508E7F9AA3BB77F4333231490F915F6D63C55FE2F08A49B353F444AD3993CACC02DB784ABBB8E42A9B1BBFFFB38BE18D78E87A0E41B9B8F73A928EE0CCEE1F6739884B9777E4FE9E88A1BBE495927AC4A799B3181D6442443","rsakv":"1330428213","is_openlock":0,"showpin":1,"exectime":64})
    return if $json->{retcode}!=0;
    return $json; 
}
1;
