---
authors:
- 'Takuya ASADA syuu@dokukino.com'
title: |
    ハイパーバイザの作り方～ちゃんと理解する仮想化技術～ 
    第１０回 Intel VT-xを用いたハイパーバイザの実装その５「ユーザランドでのI/Oエミュレーション」
...

# はじめに

前回は、VMX non root modeからvmm.koへVMExitしてきたときの処理を解説しました。
今回はI/O命令によるVMExitを受けて行われるユーザランドでのエミュレーション処理を解説します。

# 解説対象のソースコードについて

本連載では、FreeBSD-CURRENTに実装されているBHyVeのソースコードを解説しています。
このソースコードは、FreeBSDのSubversionリポジトリから取得できます。
リビジョンはr245673を用いています。

お手持ちのPCにSubversionをインストールし、次のようなコマンドでソースコードを取得してください。

svn co -r245673 svn://svn.freebsd.org/base/head src

# /usr/sbin/bhyveによる仮想CPUの実行処理のおさらい

/usr/sbin/bhyveは仮想CPUの数だけスレッドを起動し、それぞれのスレッドが/dev/vmm/\${name}に対してVM_RUN ioctlを発行します(図1)。
vmm.koはioctlを受けてCPUをVMX non root modeへ切り替えゲストOSを実行します(VMEntry)。

![VM_RUN ioctl による仮想 CPU の実行イメージ](figures/part10_fig1 "図1")

VMX non root modeでハイパーバイザの介入が必要な何らかのイベントが発生すると制御がvmm.koへ戻され、イベントがトラップされます(VMExit)。

イベントの種類が/usr/sbin/bhyveでハンドルされる必要のあるものだった場合、ioctlはリターンされ、制御が/usr/sbin/bhyveへ移ります。
/usr/sbin/bhyveはイベントの種類やレジスタの値などを参照し、デバイスエミュレーションなどの処理を行います。

今回は、この/usr/sbin/bhyveでのデバイスエミュレーション処理の部分を見ていきます。

# /usr/sbin/bhyveでのI/O命令ハンドリング

前回の記事に引き続き、I/O命令でVMExitした場合について見ていきます。
VMExitに関する情報はVM_RUN ioctlの引数であるstruct vm_runのvm_exitメンバ(struct vm_exit)に書き込まれ、ioctl return時にユーザランドへコピーされます。
/usr/sbin/bhyveはこれを受け取り、vmexit->exitcodeを参照してどのようなVMExit要因だったか判定し、VMExit要因ごとの処理を呼び出します。
I/O命令でVMExitした場合のexitcodeはVM_EXIT_INOUTです。

VM_EXIT_INOUTの場合、I/Oの命令のエミュレーションに必要な情報(ポート番号、アクセス幅、書き込み値(読み込み時は不要)、I/O方向(in/out))がstruct vm_exitを介してvmm.koから渡されます。

/usr/sbin/bhyveはこの値をI/Oポートエミュレーションハンドラに渡し、I/Oポート番号からどのデバイスへのアクセスなのかを判定し、デバイスのハンドラを呼び出します。

ハンドラの実行が終わったら、/usr/sbin/bhyveはふたたびVM_RUN ioctlを発行して、ゲストマシンの実行を再開します。

では、以上のことを踏まえてソースコードの詳細を見ていきましょう。
リスト1、リスト2、リスト3、リスト4にソースコードを示します。
キャプションの丸数字で読む順番を示しています。

## vmmapi.c と bhyverun.c の解説

libvmmapiはvmm.koへのioctl, sysctlを抽象化したライブラリで、/usr/sbin/bhyve, /usr/sbin/bhyvectlはこれを呼び出すことによりvmm.koへアクセスします(リスト1)。

リスト2 bhyverun.cは/usr/sbin/bhyveの中心になるコードです。

```
リスト1 lib/libvmmapi/vmmapi.c

......(省略)......
 280:  int
 281:  vm_run(struct vmctx *ctx, int vcpu, uint64_t rip, struct vm_exit *vmexit)
 282:  {
 283:  	int error;
 284:  	struct vm_run vmrun;
 285:  
 286:  	bzero(&vmrun, sizeof(vmrun));
 287:  	vmrun.cpuid = vcpu;
 288:  	vmrun.rip = rip;
 289:  
 290:  	error = ioctl(ctx->fd, VM_RUN, &vmrun);                     (1)
 291:  	bcopy(&vmrun.vm_exit, vmexit, sizeof(struct vm_exit));      (2)
 292:  	return (error);
 293:  }
```

- \(1) 前回の記事の最後でユーザランドへreturnされたioctlはここに戻ってくる。
- \(2) vmm.koから渡されたvmexit情報をコピーしてコール元へ渡す。

```
リスト2 usr.sbin/bhyve/bhyverun.c

......(省略)......
 294:  static int
 295:  vmexit_inout(struct vmctx *ctx, struct vm_exit *vme, int *pvcpu)
 296:  {
 297:  	int error;
 298:  	int bytes, port, in, out;
 299:  	uint32_t eax;
 300:  	int vcpu;
 301:  
 302:  	vcpu = *pvcpu;
 303:  
 304:  	port = vme->u.inout.port;                                   (6)
 305:  	bytes = vme->u.inout.bytes;
 306:  	eax = vme->u.inout.eax;
 307:  	in = vme->u.inout.in;
 308:  	out = !in;
 309:  
......(省略)......
 322:  	error = emulate_inout(ctx, vcpu, in, port, bytes, &eax, strictio);  (7)
 323:  	if (error == 0 && in)                                       (16)
 324:  		error = vm_set_register(ctx, vcpu, VM_REG_GUEST_RAX, eax);
 325:  
 326:  	if (error == 0)
 327:  		return (VMEXIT_CONTINUE);                               (17)
 328:  	else {
 329:  		fprintf(stderr, "Unhandled %s%c 0x%04x\n",
 330:  			in ? "in" : "out",
 331:  			bytes == 1 ? 'b' : (bytes == 2 ? 'w' : 'l'), port);
 332:  		return (vmexit_catch_inout());
 333:  	}
 334:  }
......(省略)......
 508:  static vmexit_handler_t handler[VM_EXITCODE_MAX] = {
 509:  	[VM_EXITCODE_INOUT]  = vmexit_inout,                        (5)
 510:  	[VM_EXITCODE_VMX]    = vmexit_vmx,
 511:  	[VM_EXITCODE_BOGUS]  = vmexit_bogus,
 512:  	[VM_EXITCODE_RDMSR]  = vmexit_rdmsr,
 513:  	[VM_EXITCODE_WRMSR]  = vmexit_wrmsr,
 514:  	[VM_EXITCODE_MTRAP]  = vmexit_mtrap,
 515:  	[VM_EXITCODE_PAGING] = vmexit_paging,
 516:  	[VM_EXITCODE_SPINUP_AP] = vmexit_spinup_ap,
 517:  };
 518:  
 519:  static void
 520:  vm_loop(struct vmctx *ctx, int vcpu, uint64_t rip)
 521:  {
......(省略)......
 532:  	while (1) {                                                 (19)
 533:  		error = vm_run(ctx, vcpu, rip, &vmexit[vcpu]);          (3)
 534:  		if (error != 0) {
 535:  			/*
 536:  			 * It is possible that 'vmmctl' or some other process
 537:  			 * has transitioned the vcpu to CANNOT_RUN state right
 538:  			 * before we tried to transition it to RUNNING.
 539:  			 *
 540:  			 * This is expected to be temporary so just retry.
 541:  			 */
 542:  			if (errno == EBUSY)
 543:  				continue;
 544:  			else
 545:  				break;
 546:  		}
 547:  
 548:  		prevcpu = vcpu;
 549:                  rc = (*handler[vmexit[vcpu].exitcode])(ctx, &vmexit[vcpu],
 550:                                                         &vcpu);       (4)
 551:  		switch (rc) {
 552:                  case VMEXIT_SWITCH:
 553:  			assert(guest_vcpu_mux);
 554:  			if (vcpu == -1) {
 555:  				stats.cpu_switch_rotate++;
 556:  				vcpu = fbsdrun_get_next_cpu(prevcpu);
 557:  			} else {
 558:  				stats.cpu_switch_direct++;
 559:  			}
 560:  			/* fall through */
 561:  		case VMEXIT_CONTINUE:
 562:                          rip = vmexit[vcpu].rip + vmexit[vcpu].inst_length;   (18)
 563:  			break;
 564:  		case VMEXIT_RESTART:
 565:                          rip = vmexit[vcpu].rip;
 566:  			break;
 567:  		case VMEXIT_RESET:
 568:  			exit(0);
 569:  		default:
 570:  			exit(1);
 571:  		}
 572:  	}
 573:  	fprintf(stderr, "vm_run error %d, errno %d\n", error, errno);
 574:  }
```

- \(6) VMExit時にvmm.koが取得した、in/out命令のエミュレーションに必要な情報  
        （ポート番号、アクセス幅、書き込み値（読み込み時は不要）、IO方向（in／out））を展開する。
- \(7) デバイスエミュレータを呼び出す。
- \(16) in命令だった場合は読み込んだ結果がゲストのraxレジスタにセットされる。  
        今回はoutなのでここを通らない。
- \(17) VMEXIT_CONTINUEがreturnされる。
- \(5) VM_EXITCODE_INOUTでVMExitしてきているのでvmexit_inout()が呼ばれる。
- \(19) whileループで再びvm_run()が実行され、ゲストマシンが再開される。
- \(3) ioctlから抜け、ここに戻ってくる。
- \(4) EXITCODEに対応したハンドラーを呼び出す。  
        ここではin/out命令の実行でVMExitしてきたものとして解説を進める。
- \(18) ゲストのripを１命令先に進める。

## inout.c

inout.cはI/O命令エミュレーションを行うコードです。
実際にはI/Oポートごとの各デバイスエミュレータのハンドラを管理する役割を担っており、要求を受けるとデバイスエミュレータのハンドラを呼び出します。
呼び出されたハンドラが実際のエミュレーション処理を行います。

```
リスト3 usr.sbin/bhyve/inout.c

......(省略)......
  72:  int
  73:  emulate_inout(struct vmctx *ctx, int vcpu, int in, int port, int bytes,
  74:  	      uint32_t *eax, int strict)
  75:  {
  76:  	int flags;
  77:  	uint32_t mask;
  78:  	inout_func_t handler;
  79:  	void *arg;
  80:  
  81:  	assert(port < MAX_IOPORTS);
  82:  
  83:  	handler = inout_handlers[port].handler;                     (8)
  84:  
  85:  	if (strict && handler == default_inout)
  86:  		return (-1);
  87:  
  88:  	if (!in) {
  89:  		switch (bytes) {
  90:  		case 1:
  91:  			mask = 0xff;
  92:  			break;
  93:  		case 2:
  94:  			mask = 0xffff;
  95:  			break;
  96:  		default:
  97:  			mask = 0xffffffff;
  98:  			break;
  99:  		}
 100:  		*eax = *eax & mask;
 101:  	}
 102:  
 103:  	flags = inout_handlers[port].flags;
 104:  	arg = inout_handlers[port].arg;
 105:  
 106:  	if ((in && (flags & IOPORT_F_IN)) || (!in && (flags & IOPORT_F_OUT)))
 107:  		return ((*handler)(ctx, vcpu, in, port, bytes, eax, arg));  (9)
 108:  	else
 109:  		return (-1);
 110:  }
......(省略)......
 141:  int
 142:  register_inout(struct inout_port *iop)                       (10)
 143:  {
 144:  	assert(iop->port < MAX_IOPORTS);
 145:  	inout_handlers[iop->port].name = iop->name;
 146:  	inout_handlers[iop->port].flags = iop->flags;
 147:  	inout_handlers[iop->port].handler = iop->handler;
 148:  	inout_handlers[iop->port].arg = iop->arg;
 149:  
 150:  	return (0);
 151:  }
```

- \(8) ポート番号ごとに登録されているIOポートハンドラを取り出す。
- \(9) ポート番号ごとに登録されているハンドラを取り出す。
- \(10) IOポートハンドラはregister_inout()で登録されている。

## consport.c

consport.cはBHyVe専用の準仮想化コンソールドライバです。
現在はUART(Universal Asynchronous Receiver Transmitter)エミュレータが導入されたので必ずしも使う必要がなくなったのですが、デバイスエミュレータとしては最も単純な構造をしているので、デバイスエミュレータの例として取り上げました。

```
リスト4 usr.sbin/bhyve/inout.c

......(省略)......
  95:  static void
  96:  ttywrite(unsigned char wb)
  97:  {
  98:  	(void) write(STDOUT_FILENO, &wb, 1);                        (15)
  99:  }
 100:  
 101:  static int
 102:  console_handler(struct vmctx *ctx, int vcpu, int in, int port, int bytes,
 103:  		uint32_t *eax, void *arg)
 104:  {
 105:  	static int opened;
 106:  
 107:  	if (bytes == 2 && in) {
 108:  		*eax = BVM_CONS_SIG;
 109:  		return (0);
 110:  	}
 111:  
 112:  	if (bytes != 4)
 113:  		return (-1);
 114:  
 115:  	if (!opened) {
 116:  		ttyopen();
 117:  		opened = 1;
 118:  	}
 119:  	
 120:  	if (in)                                                     (13)
 121:  		*eax = ttyread();
 122:  	else
 123:  		ttywrite(*eax);                                         (14)
 124:  
 125:  	return (0);
 126:  }
 127:  
 128:  static struct inout_port consport = {
 129:  	"bvmcons",
 130:  	BVM_CONSOLE_PORT,
 131:  	IOPORT_F_INOUT,
 132:  	console_handler                                             (12)
 133:  };
 134:  
 135:  void
 136:  init_bvmcons(void)
 137:  {
 138:  
 139:  	register_inout(&consport);                                  (11)
 140:  }
```

- \(15) ttywrite()はwrite()で標準出力に文字を書き込む。
- \(13) console_handler()ではIO方向がinならttyread()、outならttywrite()を実行し、標準入出力に対してIOを行う。
- \(14) 今回はoutが実行された場合を見ていく。  
        eaxで指定された書き込み値をttywrite()に渡している。
- \(12) 登録するハンドラ関数としてconsole_handler()が指定されている。
- \(11) consportデバイスは起動時にここでハンドラを登録している。


# まとめ

I/O命令によるVMExitを受けて行われるユーザランドでのエミュレーション処理について、ソースコードを解説しました。
今回までで、ハイパーバイザの実行サイクルに関するソースコードの解説を一通り行ったので、次回はvirtioのしくみについて見ていきます。

ライセンス
==========

Copyright (c) 2014 Takuya ASADA. 全ての原稿データ は
クリエイティブ・コモンズ 表示 - 継承 4.0 国際
ライセンスの下に提供されています。

参考文献
========
