package Mojo::SinaWeibo;
use strict;
use utf8;
use POSIX ();
# 获取图片验证码
#   api     :可选，默认值 'http://login.sina.com.cn/cgi/pin.php'
#   pcid    :必选
sub _get_pin {
    my $self = shift;
    my $verifycode;
    $self->info("正在获取验证码图片...");
    my %opt  = @_;
    my $api = $opt{api} || 'http://login.sina.com.cn/cgi/pin.php';
    my $query_string = {
        r   => POSIX::floor(rand() * (10**8)),
        s   => 0,
        p   => $opt{pcid},
    };
    $self->http_get($api,{is_blocking=>1},form=>$query_string,sub{
        my $data = shift;
        if(not defined $data){
            $self->error("验证码下载失败");
            return;
        }
        if(open my $fd,"<",$self->verifycode_path){
            binmode $fd;
            print $fd $data;
            close $fd;    
            $self->info("二维码已保存到本地文件[ $self->verifycode_path ]");
            $self->info("请输入图片验证码: ");
            chomp($verifycode=<STDIN>);
            return $verifycode;
        }
        else{
            $self->error("验证码写入文件[ $self->verifycode_path ]失败: $!");
            return;
        }
    });
}
1;
