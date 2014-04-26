---
authors:
- 'Takuya ASADA syuu@dokukino.com'
title: |
    ハイパーバイザの作り方～ちゃんと理解する仮想化技術～ 
    第１９回 bhyveにおける仮想NICの実装
references:
- id: part3
  title: 第３回 I/O 仮想化「デバイス I/O 編」
  URL: 'http://syuu1228.github.io/howto_implement_hypervisor/part3.pdf'
- id: part11
  title: 第１１回 virtioによる準仮想化デバイス その１「virtioの概要とVirtio PCI」
  URL: 'http://syuu1228.github.io/howto_implement_hypervisor/part11.pdf'
- id: part12
  title: 第１２回 virtioによる準仮想化デバイス その２「Virtqueueとvirtio-netの実現」
  URL: 'http://syuu1228.github.io/howto_implement_hypervisor/part12.pdf'
...

はじめに
========
これまでに、ゲスト上で発生したIOアクセスのハンドリング方法、virtio-netの仕組みなど、仮想NICの実現方法について解説してきました。
今回の記事では、/usr/sbin/bhyveが、仮想NICのインタフェースであるvirt-netに届いたパケットをどのように送受信しているのかを解説していきます。

bhyveにおける仮想NICの実装
==========================
bhyveでは、ユーザプロセスである/usr/sbin/bhyve にて仮想IOデバイスを提供しています。また、仮想IOデバイスの一つであるNICは、TAPを利用して機能を提供しています。
bhyveでは仮想NICであるTAPを物理NICとブリッジすることにより、物理NICが接続されているLANへ参加させることができます（図１）。

どのような経路を経て物理NICへとパケットが送出されていくのか、ゲストOSがパケットを送信しようとした場合を例として見てみましょう。

![パケット送信手順](figures/part19_fig1)

1. NICへのI/O通知
-----------------
ゲストOSはvirtio-netドライバを用いて、共有メモリ上のリングバッファにパケットを書き込み、IOポートアクセスによってハイパーバイザにパケット送出を通知します。IOポートアクセスによってVMExitが発生し、CPUの制御がホストOSのvmm.koのコードに戻ります[^1]。vmm.koはこのVMExitを受けてioctlをreturnし、ユーザランドプロセスである/usr/sbin/bhyveへ制御を移します。

2. 共有メモリからパケット取り出し
---------------------------------
ioctlのreturnを受け取った/usr/sbin/bhyveは仮想NICの共有メモリ上のリングバッファからパケットを取り出します[^2]。

3. tap経由でパケット送信
------------------------
２で取り出したパケットをwrite()システムコールで/dev/net/tunへ書き込みます。

4. bridge経由で物理NICへ送信
----------------------------
TAPはブリッジを経由して物理NICへパケットを送出します。

受信処理ではこの逆の流れを辿り、物理NICからtapを経由して/usr/sbin/bhyveへ届いたパケットがvirtio-netのインタフェースを通じてゲストOSへ渡されます。

[^1]: I/Oアクセスの仮想化とVMExitについては連載 @part3 を参照してください。
[^2]: 仮想NICのデータ構造とインタフェースの詳細に関しては、連載 @part11 ・@part12 を参照して下さい。

TAPとは
=======

bhyveで利用されているTAPについてもう少し詳しくみていきましょう。TAPはFreeBSDカーネルに実装された仮想Ethernetデバイスで、ハイパーバイザ／エミュレータ以外ではVPNの実装によく使われています[^3]。

物理NIC用のドライバは物理NICとの間でパケットの送受信処理を行いますが、TAPは/dev/net/tunを通じてユーザプロセスとの間でパケットの送受信処理を行います。このユーザプロセスがSocket APIを通じて、TCPv4でVPNプロトコルを用いて対向ノードとパケットのやりとりを行えば、TAPは対向ノードにレイヤ２で直接接続されたイーサーネットデバイスに見えます。

これがOpenVPNなどのVPNソフトがTAPを用いて実現している機能です（図２）。

では、ここでTAPがどのようなインタフェースをユーザプロセスに提供しているのか見ていきましょう。
TAPに届いたパケットをUDPでトンネリングするサンプルプログラムの例をコードリスト１に示します。

#### コードリスト１，TAPサンプルプログラム（Ruby）
```
require "socket"
TUNSETIFF = 0x400454ca
IFF_TAP = 0x0002
PEER = "192.168.0.100"
PORT = 9876
# TUNTAPをオープン
tap = open("/dev/net/tun", “r+")
# TUNTAPのモードをTAPに、インタフェース名を”tapN”に設定
tap.ioctl(TUNSETIFF, ["tap%d", IFF_TAP].pack("a16S"))
# UDPソケットをオープン
sock = UDPSocket.open
# ポート9876をLISTEN
sock.bind("0.0.0.0", 9876)
while true
    # ソケットかTAPにパケットが届くまで待つ
    ret = IO::select([sock, tap])
    ret[0].each do |d|
        if d == tap # TAPにパケットが届いた場合
            # TAPからパケットを読み込んでソケットに書き込み
            sock.send(tap.read(1500), 0, Socket.pack_sockaddr_in(PORT, PEER))
        else # ソケットにパケットが届いた場合
            # ソケットからパケットを読み込んでTAPに書き込み
            tap.write(sock.recv(65535))
        end
    end
end
```

ユーザプロセスがTAPとやりとりを行うには、/dev/net/tunデバイスファイルを用います。

パケットの送受信は通常のファイルIOと同様にread()、write()を用いる事が出来ますが、送受信処理を始める前にTUNSETIFF ioctlを用いてTAPの初期化を行う必要があります。
ここでは、TUNTAPのモード（TUNを使うかTAPを使うか）とifconfigに表示されるインタフェース名の指定を行います。

ここでTAPに届いたパケットをUDPソケットへ、UDPソケットに届いたパケットをTAPへ流すことにより、TAPを出入りするパケットをUDPで他ノードへトンネリングすることが出来ます（図２右相当の処理）。

![通常のNICドライバを使ったネットワークとTAPを使ったVPNの比較](figures/part19_fig2)

[^3]: 正確にはTUN/TAPとして知られており、TAPがイーサネットレイヤでパケットを送受信するインタフェースを提供するのに対しTUNデバイスはIPレイヤでパケットを送受信するインタフェースを提供します。また、TUN/TAPはFreeBSDの他にもLinux、Windows、OS Xなど主要なOSで実装されています。

bhyveにおける仮想NICとTAP
=========================
VPNソフトではTAPを通じて届いたパケットをユーザプロセスからVPNプロトコルでカプセル化して別ノード送っています。

ハイパーバイザでTAPを用いる理由はこれとは異なり、ホストOSのネットワークスタックに仮想NICを認識させ物理ネットワークに接続し、パケットを送受信するのが目的です。
このため、VPNソフトではソケットとTAPの間でパケットをリダイレクトしていたのに対して、ハイパーバイザでは仮想NICとTAPの間でパケットをリダイレクトする事になります。

それでは、このリダイレクトの部分についてbhyveのコードを実際に確認してみましょう（リスト２）。

#### コードリスト２，/usr/sbin/bhyveの仮想NICパケット受信処理
```
/* TAPからデータが届いた時に呼ばれる */
static void
pci_vtnet_tap_rx(struct pci_vtnet_softc *sc)
{
    struct vqueue_info *vq;
    struct virtio_net_rxhdr *vrx;
    uint8_t *buf;
    int len;
    struct iovec iov;
    〜 略 〜
    vq = &sc->vsc_queues[VTNET_RXQ];
    vq_startchains(vq);
    〜 略 〜
    do {
    〜 略 〜
        /* 受信キュー上の空きキューを取得 */
        assert(vq_getchain(vq, &iov, 1, NULL) == 1);
    〜 略 〜
        vrx = iov.iov_base;
        buf = (uint8_t *)(vrx + 1); /* 空きキューのアドレス */
        /* TAPから空きキューへパケットをコピー */
        len = read(sc->vsc_tapfd, buf,
        iov.iov_len - sizeof(struct virtio_net_rxhdr));
        /* TAPにデータが無ければreturn */
        if (len < 0 && errno == EWOULDBLOCK) {
    〜 略 〜
            vq_endchains(vq, 0);
            return;
        }
    〜 略 〜
        memset(vrx, 0, sizeof(struct virtio_net_rxhdr));
        vrx->vrh_bufs = 1; /* キューに接続されているバッファ数 */
    〜 略 〜
        vq_relchain(vq, len + sizeof(struct virtio_net_rxhdr));
    } while (vq_has_descs(vq)); /* 空きキューがある間繰り返し */
〜 略 〜
    vq_endchains(vq, 1);
}
```

この関数はsc->vsc_tapfdをkqueue()/kevent()でポーリングしているスレッドによってTAPへのパケット着信時コールバックされます。
コードの中では、virtio-netの受信キュー上の空きエリアを探して、TAPからキューが示すバッファにデータをコピーしています。
これによって、TAPへパケットが届いた時は仮想NICへ送られ、仮想NICからパケットが届いた時はゲストOSに送られます。
その結果、bhyveの仮想NICはホストOSにとってLANケーブルでtap0へ接続されているような状態になります。

TAPを用いたネットワークの構成方法
=================================
前述の状態になった仮想NICでは、IPアドレスが適切に設定されていればホストOSとゲストOS間の通信が問題なく行えるようになります。しかしながら、このままではホストとの間でしか通信ができず、インターネットやLAN上の他ノードに接続する方法がありません。この点においては、2台のPCをLANケーブルで物理的に直接つないている環境と同じです。

これを解決するには、ホストOS側に標準的に搭載されているネットワーク機能を利用します。1つの方法は、すでに紹介したブリッジを使う方法で、TAPと物理NICをデータリンクレイヤで接続し、物理NICの接続されているネットワークにTAPを参加させることます。しかしながら、WiFiでは仕様によりブリッジが動作しないという制限があったり、LANから1つの物理PCに対して複数のIP付与が許可されていない環境で使う場合など、ブリッジ以外の方法でゲストのネットワークを運用したい場合があります。

この場合は、NATを使ってホストOSでアドレス変換を行ったうえでIPレイヤでルーティングを行います[^4]。bhyveではこれらの設定を自動的に行うしくみをとくに提供しておらず、TAPにbhyveを接続する機能だけを備えているので、自分でコンフィギュレーションを行う必要があります。

リスト3、4に/etc/rc.confの設定例を示します。なお、OpenVPNなどを用いたVPN接続に対してブリッジやNATを行う場合も、ほぼ同じ設定が必要になります。

#### リスト3，ブリッジの場合
```
cloned_interfaces="bridge0 tap0"
autobridge_interfaces="bridge0"
autobridge_bridge0="em0 tap*"
ifconfig_bridge0="up"
```

#### リスト4，NATの場合
```
firewall_enable="YES"
firewall_type="OPEN"
natd_enable="YES"
natd_interface="em0"
gateway_enable="YES"
cloned_interfaces="tap0"
ifconfig_tap0="inet 192.168.100.1/24 up"
dnsmasq_enable="YES"
```

[^4]:NATを使わずにルーティングだけを行うこともできますが、その場合はLAN上のノードからゲストネットワークへの経路が設定されていなければなりません。一般的にはそのような運用は考えにくいので、NATを使うことがほとんどのケースで適切だと思われます。

まとめ
======

今回は仮想マシンのネットワークデバイスについて解説しました。
次回は、仮想マシンのストレージデバイスについて解説します。

ライセンス
==========

Copyright (c) 2014 Takuya ASADA. 全ての原稿データ は
クリエイティブ・コモンズ 表示 - 継承 4.0 国際
ライセンスの下に提供されています。

参考文献
========

