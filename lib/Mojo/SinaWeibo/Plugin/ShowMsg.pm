package Mojo::SinaWeibo::Plugin::ShowMsg;
our $PRIORITY = 100;
use POSIX qw(strftime);
sub call{
    my $client = shift;
    $client->on(send_message=>sub{
        my($client,$msg) = @_;
        my $attach = $msg->is_success?"":"[发送失败".(defined $msg->status?"(".$msg->status.")":"") . "]";
        my $sender_nick = "我";
        $client->info({time=>$msg->time,level=>"微博消息",title=>"$sender_nick :"},$msg->content . $attach)
    });
}

1
