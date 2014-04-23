---
authors:
- 'Takuya ASADA syuu@dokukino.com'
title: |
    ハイパーバイザの作り方～ちゃんと理解する仮想化技術～ 付属資料
    最近のPCアーキテクチャにおける割り込みルーティングの仕組み
...

はじめに
========

Linuxにおける/proc/irq/\<IRQ\>/smp\_affinityはハードウェアにどのような設定を行うことにより実現されているのか、或いは最近のPCアーキテクチャにおける割り込みの仕組みはどうなっているのか、という辺りが知りたかったので調べてみた。

結構こんがらがっているので、予想外に時間を食ってしまった…まだ調べ尽くせていないが、一旦現時点での理解を書いておこうと思う。

前提条件
========

1.  2つ以上のCPUコアを持つ、Core2世代或いはCore iシリーズ世代のIntel
    CPU／チップセット

2.  割り込みを行う主体はPCIeデバイスである（主にNICを想定しているが、これに限定されない）

3.  Legacyな8259割り込みコントローラを使うことは考慮しない

4.  x86\_64向けLinuxカーネル（解析に使っているバージョンは3.2.0+）が動作している

5.  仮想化は使用しない

PCIeに於ける割り込みの種類
==========================

レガシー割り込み（INTx）
------------------------

PCI規格に最初から用意されていた割り込み方法で、大半のPCIデバイスはこの割り込みを用いている。
PCIバスのメインラインとは別に用意された割り込み用の物理的なピンを用いて割り込みを通知する。

PCIeには割り込み用ピンは用意されておらず、帯域内メッセージを用いるレガシー割り込みエミュレーションによってソフト的な互換性を維持しているものの、基本的にはMSI／MSI-X割り込みへ移行することが推奨されているものと思われる。

MSI割り込み
-----------

PCI
2.3から追加された割り込みモードでピンを使用しない帯域内メッセージで割り込みを行う。
デバイスあたり最大32個のMSIメッセージをサポートしている。

MSI-X割り込み
-------------

PCI 3.0ではオプションとされPCIe
1.0から必須とされた割り込みモードで、MSI割り込みの拡張版。
デバイスあたり最大2048個のメッセージをサポートしている。

割り込みルーティング
====================

レガシー割り込み
----------------

デバイスからピン経由で割り込みを通知→IOAPICでRedirection Table
Entryを参照、通知先LAPICを決定→CPU内のLAPICへ割り込みを通知

MSI割り込み
-----------

デバイスはPCI Configuration SpaceのCapability
Structure内のMSIフィールドを参照、MSI AddressレジスタとMSI
Dataレジスタの値から通知先LAPICとLAPIC上のベクタ番号を決定→CPU内のLAPICへ割り込みを通知

MSI-X割り込み
-------------

レジスタの構成が異なる（ベクタ毎にAddressとDataが用意されている）が基本的な仕組みはMSI割り込みと同様

Capability Structure
--------------------

@BIOSInitを見るとイメージが分かると思うが、Configuration SpaceからLinked
List状に複数のcapabilityが繋がる構造になっていて、CAPIDが0xd0なのがMSIのフィールドで、ここにはMSICTL,
MSIAR, MSIDRの3つのレジスタがある。

MSI Control Register(MSICTL)
----------------------------

どのCPUに割り込むかを考える上では重要ではないので省略

MSI Address Register(MSIAR)
---------------------------

-   31:20 = 0xfee

-   19:12 = Destination ID

-   11:4 = IA32では未使用

-   3 = Address Redirection Hint(RH)

    -   0: Directed

    -   1: Redirectable

-   2 = Address Destination Mode(DM)

    -   0: Physical Mode

    -   1: Logical Mode

-   1:0 = 予約

Destination ModeがLogicalかつRedirection
HintがRedirectableな場合はDestination
IDでビットが立っているCPUの中でTask Priority
Register(TPR)が最も低いCPUのLAPICへ割り込みが送られる。 それ以外のRH,
DMの組み合わせではDestination
IDで指定されているビットの中で特定のCPUのLAPICへ割り込みが送られる。

Physical ModeでDestination
IDが0xffの場合はブロードキャスト割り込みを行う。

MSI Data Register(MSIDR)
------------------------

-   31:16 = 0x0000

-   15 = Trigger mode

    -   0: Edge

    -   1: Level

-   14 = Delivery status

    -   0: Deassert

    -   1: Assert

-   13:12 = 0x00

-   11:8 = Delivery mode

    -   0000: Fixed

    -   0001: Lowest priority

    -   0010: SMI/PMI/MCA

    -   0011: Reserved

    -   0100: NMI

    -   0101: INIT

    -   0110: Reserved

    -   0111: ExtINT

    -   1000-1111: Reserved

-   7:0 = Interrupt Vector

Delivery
modeがFixedの場合はDestinationに指定された全てのCPUへ割り込みを行う。
Lowest Priorityの場合はTask Priority
Registerの値が最も低いCPUへ割り込みを行う。 Interrupt
Vectorに割り込み先LAPICのVector番号を指定。

Linuxカーネルで実際にレジスタの値を設定している所を見てみる
-----------------------------------------------------------

msi\_compose\_msg[^1]でレジスタに書き込みたい値を用意しているので、これを見てみる。
$msg->address\_lo$がMSIARレジスタで、$apic->irq\_dest\_mode$が0ならphysical
mode、1ならlogical
modeを設定、$apic->irq\_delivery\_mode$がdest\_LowestPrioならRedirectable（MSI\_ADDR\_REDIRECTION\_LOWPRI）を、そうでなければDirected（MSI\_ADDR\_REDIRECTION\_CPU）を設定、変数destをDestination
IDとして設定している。

$msg->data$がMSIDRレジスタで、$apic->irq\_delivery\_mode$がdest\_LowestPrioならLowest
priorityを、そうでなければFixedを設定、$cfg->vector$の値をInterrupt
Vectorとして設定している。

$apic->irq\_dest\_mode$と$apic->irq\_delivery\_mode$の値はIO
APICのドライバ毎に違うのだが、x86\_64の標準ドライバのapic\_flat\_64.c[^2]ではirq\_dest\_modeは1,
irq\_delivery\_modeはdest\_LowestPrioに設定されている。

これらの値は割り込み初期化時に設定され、/proc/irq/\<IRQ\>/smp\_affinityの書き換え時にも維持される。
smp\_affinityの書き換え時には、Destination IDとInterrupt
Vectorだけが変更される[^3]。

全ての環境でLogical modeかつLowest
priorityが使えるとは限らないので、場合によってはPhysical
Modeで初期化されていてsmp\_affinityの値を0xffにしてもCPU0にしか割り込まないという挙動を行う事も有り得る。
実際、論理CPUが12個あるCore i7上でLinux
3.2.0+を走らせている環境ではExtended Physical
Modeで初期化されていて、割り込み分散が行われていなかった。

$/proc/irq/<IRQ>/smp\_affinity$の書き換えでPCIコンフィグレーション空間はどのように書き換わるか
----------------------------------------------------------------------------------------------

例えばThinkpad x200にはこんなデバイスがあります。 （dmesgから抜粋）

[H]

    e1000e: Intel(R) PRO/1000 Network Driver - 1.5.1-k
    e1000e: Copyright(c) 1999 - 2011 Intel Corporation.
    e1000e 0000:00:19.0: PCI INT A -> GSI 20 (level, low) -> IRQ 20
    e1000e 0000:00:19.0: setting latency timer to 64
    e1000e 0000:00:19.0: irq 44 for MSI/MSI-X
    e1000e 0000:00:19.0: eth0: (PCI Express:2.5GT/s:Width x1) 00:1f:16:2a:a4:59
    e1000e 0000:00:19.0: eth0: Intel(R) PRO/1000 Network Connection
    e1000e 0000:00:19.0: eth0: MAC: 7, PHY: 8, PBA No: 1008FF-0FF
    udev[16200]: renamed network interface eth0 to eth4

IRQ44のMSI割り込みを一つ持つe1000eで、PCIのアドレスは00:19.0ですね。

[H]

    # cat /proc/irq/44/smp_affinity
    3

CPUはcpu0とcpu1なので、全てのCPUのビットを立ててるから3。

[H]

    # grep eth4 /proc/interrupts 
     44:      50037      49330   PCI-MSI-edge      eth4

設定通り、両側のCPUに割り込んでますね。 この時、MSI Address
RegisterとMSI Data
Registerにはどのような値が設定されているか確認してみます。

[H]

    # lspci -vvvv -s 00:19.0
    00:19.0 Ethernet controller: Intel Corporation 82567LM Gigabit Network Connection (rev 03)
        Subsystem: Lenovo Device 20ee
        Control: I/O+ Mem+ BusMaster+ SpecCycle- MemWINV- VGASnoop- ParErr- Stepping- SERR+ FastB2B- DisINTx+
        Status: Cap+ 66MHz- UDF- FastB2B- ParErr- DEVSEL=fast >TAbort- <TAbort- <MAbort- >SERR- <PERR- INTx-
        Latency: 0
        Interrupt: pin A routed to IRQ 44
        Region 0: Memory at f2600000 (32-bit, non-prefetchable) [size=128K]
        Region 1: Memory at f2625000 (32-bit, non-prefetchable) [size=4K]
        Region 2: I/O ports at 1840 [size=32]
        Capabilities: [c8] Power Management version 2
            Flags: PMEClk- DSI+ D1- D2- AuxCurrent=0mA PME(D0+,D1-,D2-,D3hot+,D3cold+)
            Status: D0 NoSoftRst- PME-Enable- DSel=0 DScale=1 PME-
        Capabilities: [d0] MSI: Enable+ Count=1/1 Maskable- 64bit+
            Address: 00000000fee0300c  Data: 41b9
        Capabilities: [e0] PCI Advanced Features
            AFCap: TP+ FLR+
            AFCtrl: FLR-
            AFStatus: TP-
        Kernel driver in use: e1000e
        Kernel modules: e1000e

「Capabilities: [d0]
MSI」の「Address」と「Data」の所ですが、これをビットフィールドと突き合わせて読まないといけません。
分かりにくいですね。
なので、lspciを改造してわかり易く表示出来るようにしてみます。

こちらが改造後のコード[^4]になります。 早速実行してみます。

[H]

    # gcc -lpci msireg.c
    # ./a.out 00:19.0
    Message Signalled Interrupts: 64bit+ Queue=0/0 Enable+
    address_hi=0
    address_lo=fee0300c dest_mode=logical redirection=lowpri dest_id=3
    data=41b9 trigger=edge level=assert delivery_mode=lowpri vector=185

Logical modeでLowpri、destid=3、vector=185になってるのが分かります。
ここでsmp\_affinityを変えてみましょう。

[H]

    # echo 1 > /proc/irq/44/smp_affinity
    # ./a.out 00:19.0
    Message Signalled Interrupts: 64bit+ Queue=0/0 Enable+
    address_hi=0
    address_lo=fee0100c dest_mode=logical redirection=lowpri dest_id=1
    data=41b9 trigger=edge level=assert delivery_mode=lowpri vector=185

dest\_idが1に書き換わったのが見て取れます。

<span>5</span> BIOSがPCI Expressを初期化する手順が見えてきた:
なひたふJTAG日記
<http://nahitafu.cocolog-nifty.com/nahitafu/2007/02/pci_express_2b63.html>
Intel® 64 and IA-32 Architectures Software Developer Manuals
<http://www.intel.com/content/www/us/en/processors/architectures-software-developer-manuals.html>
Intel® 5520/5500 Chipset: Datasheet
<http://www.intel.com/content/www/us/en/chipsets/5520-5500-chipset-ioh-datasheet.html>
PCI Local Bus Specification Revision 3.0 PCI Express 2.0 Base
Specification Revision 0.9

[^1]: <http://lxr.linux.no/linux+v3.2/arch/x86/kernel/apic/io_apic.c#L3167>

[^2]: <http://lxr.linux.no/linux+v3.2/arch/x86/kernel/apic/apic_flat_64.c#L180>

[^3]: <http://lxr.linux.no/linux+v3.2/arch/x86/kernel/apic/io_apic.c#L3201>

[^4]: <https://gist.github.com/1568777>
