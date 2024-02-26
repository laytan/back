package elf

EI_Class :: enum byte {
	Bits_32 = 1,
	Bits_64 = 2,
}

EI_Data :: enum byte {
	Little = 1,
	Big    = 2,
}

Version :: enum byte {
	Current = 1,
}

EI_OSABI :: enum byte {
	Sysv       = 0,
	Hpux       = 1,
	Netbsd     = 2,
	Linux      = 3,
	Hurd       = 4,
	Solaris    = 6,
	Aix        = 7,
	Irix       = 8,
	Freebsd    = 9,
	Tru64      = 10,
	Modesto    = 11,
	Openbsd    = 12,
	Openvms    = 13,
	Nsk        = 14,
	Aros       = 15,
	Fenixos    = 16,
	Cloud      = 17,
	Sortix     = 53,
	Arm_AE     = 64,
	Arm        = 97,
	Cell_LV2   = 102,
	Standalone = 255,
}

Type :: enum u16 /* endian specific */ {
	Rel     = 1,
	Exec    = 2,
	Dyn     = 3,
	Core    = 4,
	Lo_Proc = 0xff00,
	Hi_Proc = 0xffff,
}

Machine :: enum u16 /* endian specific */ {
	NONE          = 0,      // No machine
    M32           = 1,      // AT&T WE 32100
    SPARC         = 2,      // SPARC
    EM_386        = 3,      // Intel 80386
    EM_68K        = 4,      // Motorola 68000
    EM_88K        = 5,      // Motorola 88000
    IAMCU         = 6,      // Intel MCU
    EM_860        = 7,      // Intel 80860
    MIPS          = 8,      // MIPS I Architecture
    S370          = 9,      // IBM System/370 Processor
    MIPS_RS3_LE   = 10,     // MIPS RS3000 Little-endian
    PARISC        = 15,     // Hewlett-Packard PA-RISC
    VPP500        = 17,     // Fujitsu VPP500
    SPARC32PLUS   = 18,     // Enhanced instruction set SPARC
    EM_960        = 19,     // Intel 80960
    PPC           = 20,     // PowerPC
    PPC64         = 21,     // 64-bit PowerPC
    S390          = 22,     // IBM System/390 Processor
    SPU           = 23,     // IBM SPU/SPC
    V800          = 36,     // NEC V800
    FR20          = 37,     // Fujitsu FR20
    RH32          = 38,     // TRW RH-32
    RCE           = 39,     // Motorola RCE
    ARM           = 40,     // ARM 32-bit architecture (AARCH32)
    ALPHA         = 41,     // Digital Alpha
    SH            = 42,     // Hitachi SH
    SPARCV9       = 43,     // SPARC Version 9
    TRICORE       = 44,     // Siemens TriCore embedded processor
    ARC           = 45,     // Argonaut RISC Core, Argonaut Technologies Inc.
    H8_300        = 46,     // Hitachi H8/300
    H8_300H       = 47,     // Hitachi H8/300H
    H8S           = 48,     // Hitachi H8S
    H8_500        = 49,     // Hitachi H8/500
    IA_64         = 50,     // Intel IA-64 processor architecture
    MIPS_X        = 51,     // Stanford MIPS-X
    COLDFIRE      = 52,     // Motorola ColdFire
    EM_68HC12     = 53,     // Motorola M68HC12
    MMA           = 54,     // Fujitsu MMA Multimedia Accelerator
    PCP           = 55,     // Siemens PCP
    NCPU          = 56,     // Sony nCPU embedded RISC processor
    NDR1          = 57,     // Denso NDR1 microprocessor
    STARCORE      = 58,     // Motorola Star*Core processor
    ME16          = 59,     // Toyota ME16 processor
    ST100         = 60,     // STMicroelectronics ST100 processor
    TINYJ         = 61,     // Advanced Logic Corp. TinyJ embedded processor family
    X86_64        = 62,     // AMD x86-64 architecture
    PDSP          = 63,     // Sony DSP Processor
    PDP10         = 64,     // Digital Equipment Corp. PDP-10
    PDP11         = 65,     // Digital Equipment Corp. PDP-11
    FX66          = 66,     // Siemens FX66 microcontroller
    ST9PLUS       = 67,     // STMicroelectronics ST9+ 8/16 bit microcontroller
    ST7           = 68,     // STMicroelectronics ST7 8-bit microcontroller
    EM_68HC16     = 69,     // Motorola MC68HC16 Microcontroller
    EM_68HC11     = 70,     // Motorola MC68HC11 Microcontroller
    EM_68HC08     = 71,     // Motorola MC68HC08 Microcontroller
    EM_68HC05     = 72,     // Motorola MC68HC05 Microcontroller
    SVX           = 73,     // Silicon Graphics SVx
    ST19          = 74,     // STMicroelectronics ST19 8-bit microcontroller
    VAX           = 75,     // Digital VAX
    CRIS          = 76,     // Axis Communications 32-bit embedded processor
    JAVELIN       = 77,     // Infineon Technologies 32-bit embedded processor
    FIREPATH      = 78,     // Element 14 64-bit DSP Processor
    ZSP           = 79,     // LSI Logic 16-bit DSP Processor
    MMIX          = 80,     // Donald Knuth's educational 64-bit processor
    HUANY         = 81,     // Harvard University machine-independent object files
    PRISM         = 82,     // SiTera Prism
    AVR           = 83,     // Atmel AVR 8-bit microcontroller
    FR30          = 84,     // Fujitsu FR30
    D10V          = 85,     // Mitsubishi D10V
    D30V          = 86,     // Mitsubishi D30V
    V850          = 87,     // NEC v850
    M32R          = 88,     // Mitsubishi M32R
    MN10300       = 89,     // Matsushita MN10300
    MN10200       = 90,     // Matsushita MN10200
    PJ            = 91,     // picoJava
    OPENRISC      = 92,     // OpenRISC 32-bit embedded processor
    ARC_COMPACT   = 93,     // ARC International ARCompact processor (old spelling/synonym: EM_ARC_A5)
    XTENSA        = 94,     // Tensilica Xtensa Architecture
    VIDEOCORE     = 95,     // Alphamosaic VideoCore processor
    TMM_GPP       = 96,     // Thompson Multimedia General Purpose Processor
    NS32K         = 97,     // National Semiconductor 32000 series
    TPC           = 98,     // Tenor Network TPC processor
    SNP1K         = 99,     // Trebia SNP 1000 processor
    ST200         = 100,    // STMicroelectronics (www.st.com) ST200 microcontroller
    IP2K          = 101,    // Ubicom IP2xxx microcontroller family
    MAX           = 102,    // MAX Processor
    CR            = 103,    // National Semiconductor CompactRISC microprocessor
    F2MC16        = 104,    // Fujitsu F2MC16
    MSP430        = 105,    // Texas Instruments embedded microcontroller msp430
    BLACKFIN      = 106,    // Analog Devices Blackfin (DSP) processor
    SE_C33        = 107,    // S1C33 Family of Seiko Epson processors
    SEP           = 108,    // Sharp embedded microprocessor
    ARCA          = 109,    // Arca RISC Microprocessor
    UNICORE       = 110,    // Microprocessor series from PKU-Unity Ltd. and MPRC of Peking University
    EXCESS        = 111,    // eXcess: 16/32/64-bit configurable embedded CPU
    DXP           = 112,    // Icera Semiconductor Inc. Deep Execution Processor
    ALTERA_NIOS2  = 113,    // Altera Nios II soft-core processor
    CRX           = 114,    // National Semiconductor CompactRISC CRX microprocessor
    XGATE         = 115,    // Motorola XGATE embedded processor
    C166          = 116,    // Infineon C16x/XC16x processor
    M16C          = 117,    // Renesas M16C series microprocessors
    DSPIC30F      = 118,    // Microchip Technology dsPIC30F Digital Signal Controller
    CE            = 119,    // Freescale Communication Engine RISC core
    M32C          = 120,    // Renesas M32C series microprocessors
    TSK3000       = 131,    // Altium TSK3000 core
    RS08          = 132,    // Freescale RS08 embedded processor
    SHARC         = 133,    // Analog Devices SHARC family of 32-bit DSP processors
    ECOG2         = 134,    // Cyan Technology eCOG2 microprocessor
    SCORE7        = 135,    // Sunplus S+core7 RISC processor
    DSP24         = 136,    // New Japan Radio (NJR) 24-bit DSP Processor
    VIDEOCORE3    = 137,    // Broadcom VideoCore III processor
    LATTICEMICO32 = 138,    // RISC processor for Lattice FPGA architecture
    SE_C17        = 139,    // Seiko Epson C17 family
    TI_C6000      = 140,    // The Texas Instruments TMS320C6000 DSP family
    TI_C2000      = 141,    // The Texas Instruments TMS320C2000 DSP family
    TI_C5500      = 142,    // The Texas Instruments TMS320C55x DSP family
    TI_ARP32      = 143,    // Texas Instruments Application Specific RISC Processor, 32bit fetch
    TI_PRU        = 144,    // Texas Instruments Programmable Realtime Unit
    MMDSP_PLUS    = 160,    // STMicroelectronics 64bit VLIW Data Signal Processor
    CYPRESS_M8C   = 161,    // Cypress M8C microprocessor
    R32C          = 162,    // Renesas R32C series microprocessors
    TRIMEDIA      = 163,    // NXP Semiconductors TriMedia architecture family
    QDSP6         = 164,    // QUALCOMM DSP6 Processor
    EM_8051       = 165,    // Intel 8051 and variants
    STXP7X        = 166,    // STMicroelectronics STxP7x family of configurable and extensible RISC processors
    NDS32         = 167,    // Andes Technology compact code size embedded RISC processor family
    ECOG1         = 168,    // Cyan Technology eCOG1X family
    ECOG1X        = 168,    // Cyan Technology eCOG1X family
    MAXQ30        = 169,    // Dallas Semiconductor MAXQ30 Core Micro-controllers
    XIMO16        = 170,    // New Japan Radio (NJR) 16-bit DSP Processor
    MANIK         = 171,    // M2000 Reconfigurable RISC Microprocessor
    CRAYNV2       = 172,    // Cray Inc. NV2 vector architecture
    RX            = 173,    // Renesas RX family
    METAG         = 174,    // Imagination Technologies META processor architecture
    MCST_ELBRUS   = 175,    // MCST Elbrus general purpose hardware architecture
    ECOG16        = 176,    // Cyan Technology eCOG16 family
    CR16          = 177,    // National Semiconductor CompactRISC CR16 16-bit microprocessor
    ETPU          = 178,    // Freescale Extended Time Processing Unit
    SLE9X         = 179,    // Infineon Technologies SLE9X core
    L10M          = 180,    // Intel L10M
    K10M          = 181,    // Intel K10M
    AARCH64       = 183,    // ARM 64-bit architecture (AARCH64)
    AVR32         = 185,    // Atmel Corporation 32-bit microprocessor family
    STM8          = 186,    // STMicroeletronics STM8 8-bit microcontroller
    TILE64        = 187,    // Tilera TILE64 multicore architecture family
    TILEPRO       = 188,    // Tilera TILEPro multicore architecture family
    MICROBLAZE    = 189,    // Xilinx MicroBlaze 32-bit RISC soft processor core
    CUDA          = 190,    // NVIDIA CUDA architecture
    TILEGX        = 191,    // Tilera TILE-Gx multicore architecture family
    CLOUDSHIELD   = 192,    // CloudShield architecture family
    COREA_1ST     = 193,    // KIPO-KAIST Core-A 1st generation processor family
    COREA_2ND     = 194,    // KIPO-KAIST Core-A 2nd generation processor family
    ARC_COMPACT2  = 195,    // Synopsys ARCompact V2
    OPEN8         = 196,    // Open8 8-bit RISC soft processor core
    RL78          = 197,    // Renesas RL78 family
    VIDEOCORE5    = 198,    // Broadcom VideoCore V processor
    EM_78KOR      = 199,    // Renesas 78KOR family
    EM_56800EX    = 200,    // Freescale 56800EX Digital Signal Controller (DSC)
    BA1           = 201,    // Beyond BA1 CPU architecture
    BA2           = 202,    // Beyond BA2 CPU architecture
    XCORE         = 203,    // XMOS xCORE processor family
    MCHP_PIC      = 204,    // Microchip 8-bit PIC(r) family
    INTEL205      = 205,    // Reserved by Intel
    INTEL206      = 206,    // Reserved by Intel
    INTEL207      = 207,    // Reserved by Intel
    INTEL208      = 208,    // Reserved by Intel
    INTEL209      = 209,    // Reserved by Intel
    KM32          = 210,    // KM211 KM32 32-bit processor
    KMX32         = 211,    // KM211 KMX32 32-bit processor
    KMX16         = 212,    // KM211 KMX16 16-bit processor
    KMX8          = 213,    // KM211 KMX8 8-bit processor
    KVARC         = 214,    // KM211 KVARC processor
    CDP           = 215,    // Paneve CDP architecture family
    COGE          = 216,    // Cognitive Smart Memory Processor
    COOL          = 217,    // Bluechip Systems CoolEngine
    NORC          = 218,    // Nanoradio Optimized RISC
    CSR_KALIMBA   = 219,    // CSR Kalimba architecture family
    Z80           = 220,    // Zilog Z80
    VISIUM        = 221,    // Controls and Data Services VISIUMcore processor
    FT32          = 222,    // FTDI Chip FT32 high performance 32-bit RISC architecture
    MOXIE         = 223,    // Moxie processor family
    AMDGPU        = 224,    // AMD GPU architecture
    RISCV         = 243,    // RISC-V
    BPF           = 247,    // Linux BPF - in-kernel virtual machine
    CSKY          = 252,    // C-SKY
    LOONGARCH     = 258,    // LoongArch
    FRV           = 0x5441, // Fujitsu FR-V
    // Reservations
    // reserved  11-14   Reserved for future use
    // reserved  16      Reserved for future use
    // reserved  24-35   Reserved for future use
    // reserved  121-130 Reserved for future use
    // reserved  145-159 Reserved for future use
    // reserved  145-159 Reserved for future use
    // reserved  182     Reserved for future Intel use
    // reserved  184     Reserved for future ARM use
    // unknown/reserve?  225 - 242
}

// The base section types enum, other processor specific types exist but aren't defined.
Section_Type :: enum u32 {
	NULL           = 0,
    PROGBITS       = 1,
    SYMTAB         = 2,
    STRTAB         = 3,
    RELA           = 4,
    HASH           = 5,
    DYNAMIC        = 6,
    NOTE           = 7,
    NOBITS         = 8,
    REL            = 9,
    SHLIB          = 10,
    DYNSYM         = 11,
    INIT_ARRAY     = 14,
    FINI_ARRAY     = 15,
    PREINIT_ARRAY  = 16,
    GROUP          = 17,
    SYMTAB_SHNDX   = 18,
    RELR           = 19,
    NUM            = 20,
    LOOS           = 0x60000000,
    GNU_ATTRIBUTES = 0x6ffffff5,
    GNU_HASH       = 0x6ffffff6,
    GNU_LIBLIST    = 0x6ffffff7,
    GNU_verdef     = 0x6ffffffd,  //  also SHT_SUNW_verdef
    GNU_verneed    = 0x6ffffffe, //  also SHT_SUNW_verneed
    GNU_versym     = 0x6fffffff,  //  also SHT_SUNW_versym, SHT_HIOS

    // These carry no semantic meaning in themselves and may be overridden by target-specific values.
    LOPROC = 0x70000000,
    HIPROC = 0x7fffffff,

    LOUSER       = 0x80000000,
    HIUSER       = 0xffffffff,
    SUNW_LDYNSYM = 0x6ffffff3,
    SUNW_syminfo = 0x6ffffffc,
}
