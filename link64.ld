OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_start)
SECTIONS
{
    . = 0xffff808000120000;

    _TEXT_START = .;
    .text BLOCK(4K) : ALIGN(4K)
    {
        *(.bootstrap)
        *(.text)
    }
    . = ALIGN(4K);
    _TEXT_END = .;

    . = ALIGN(4K);
    _DATA_START = .;
    .data BLOCK(4K) : ALIGN(4K)
    {
        *(.data)

        text_start = .; QUAD(_TEXT_START)
        text_end = .;   QUAD(_TEXT_END)
        data_start = .; QUAD(_DATA_START)
        data_end = .;   QUAD(_DATA_END)
        bss_start = .; QUAD(_BSS_START)
        bss_end = .;   QUAD(_BSS_END)
        kernel_end = .; QUAD(_KERNEL_END)
    }
    .bss BLOCK(4K) : ALIGN(4K)
    {
        _BSS_START = .;
        *(.bss)
        _BSS_END = .;
    }
    . = ALIGN(4K);
    _DATA_END = .;

    .stack BLOCK(4K) : ALIGN(4K)
    {
        *(.stack)
    }
    . = ALIGN(4K);
    _KERNEL_END = .;
}
