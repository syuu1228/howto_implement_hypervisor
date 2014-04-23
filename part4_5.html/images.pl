# LaTeX2HTML 2012 (1.2)
# Associate images original text with physical files.


$key = q/msg->address_lo;MSF=1.6;LFS=12;AAT/;
$cached_env_img{$key} = q|<IMG
 WIDTH="132" HEIGHT="27" ALIGN="MIDDLE" BORDER="0"
 SRC="|."$dir".q|img1.png"
 ALT="$msg-&gt;address\_lo$">|; 

$key = q/apic->irq_delivery_mode;MSF=1.6;LFS=12;AAT/;
$cached_env_img{$key} = q|<IMG
 WIDTH="180" HEIGHT="27" ALIGN="MIDDLE" BORDER="0"
 SRC="|."$dir".q|img3.png"
 ALT="$apic-&gt;irq\_delivery\_mode$">|; 

$key = q/msg->data;MSF=1.6;LFS=12;AAT/;
$cached_env_img{$key} = q|<IMG
 WIDTH="96" HEIGHT="27" ALIGN="MIDDLE" BORDER="0"
 SRC="|."$dir".q|img4.png"
 ALT="$msg-&gt;data$">|; 

$key = q/apic->irq_dest_mode;MSF=1.6;LFS=12;AAT/;
$cached_env_img{$key} = q|<IMG
 WIDTH="151" HEIGHT="27" ALIGN="MIDDLE" BORDER="0"
 SRC="|."$dir".q|img2.png"
 ALT="$apic-&gt;irq\_dest\_mode$">|; 

$key = q/cfg->vector;MSF=1.6;LFS=12;AAT/;
$cached_env_img{$key} = q|<IMG
 WIDTH="103" HEIGHT="28" ALIGN="MIDDLE" BORDER="0"
 SRC="|."$dir".q|img5.png"
 ALT="$cfg-&gt;vector$">|; 

1;

