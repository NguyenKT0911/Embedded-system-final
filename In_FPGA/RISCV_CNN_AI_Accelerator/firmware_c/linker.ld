ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
    DMEM (rwx) : ORIGIN = 0x80000000, LENGTH = 8K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.start))
        *(.text .text.*)
    } > IMEM

    .data :
    {
        . = ALIGN(4);
        __data_start = .;
        *(.rodata .rodata.*)
        *(.data .data.*)
        . = ALIGN(4);
        __data_end = .;
    } > DMEM

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > DMEM

    /DISCARD/ :
    {
        *(.comment)
        *(.eh_frame .eh_frame.*)
        *(.eh_frame_hdr)
    }

    __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
    ASSERT(__data_end <= __stack_top, "DMEM initialized data overflow")
    ASSERT(__bss_end <= (__stack_top - 1024), "DMEM leaves less than 1 KiB stack")
}

