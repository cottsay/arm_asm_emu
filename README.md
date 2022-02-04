# arm\_asm\_emu
A Game Boy emulator written entirely in ARM assemly language.

Why assembly language? Why not.

[![GitHub Workflow Status](https://img.shields.io/github/workflow/status/cottsay/arm_asm_emu/arm_asm_emu%20CI/main?event=push&logo=github)](https://github.com/cottsay/arm_asm_emu/actions?query=workflow%3A%22arm_asm_emu+CI%22+branch%3Amain+event%3Apush)


## Cross-assembling
The Makefile is set up for both native building on an ARM platform as well as
cross-compling. Pass your favorite cross-compiling prefix to the `make`
invocation with something like `CROSS=arm-none-eabi-`.

The testing harness can also be invoked on a non-arm platform using QEMU.
Specify something like `TEST_WRAPPER=qemu-arm` during the `make test`
invocation to use QEMU when running tests.


## Testing
A test harness has been created which runs a ROM for a given number of cycles
and checks a CRC32 of the screen contents against a set value. If the value
doesn't match, a capture of the screen is saved as a `.bmp` file and the
process returns non-zero.

At present, only the Blargg tests are targeted. Here are the current passing
tests:

| cpu\_instrs        | passing            |
| ------------------ | ------------------ |
| special            | :heavy_check_mark: |
| interrupts         | :heavy_check_mark: |
| op sp,hl           | :heavy_check_mark: |
| op r,imm           | :heavy_check_mark: |
| op rp              | :heavy_check_mark: |
| ld r,r             | :heavy_check_mark: |
| jr,jp,call,ret,rst | :heavy_check_mark: |
| misc instrs        | :heavy_check_mark: |
| op r,r             | :heavy_check_mark: |
| bit ops            | :heavy_check_mark: |
| op a,(hl)          | :heavy_check_mark: |

| timing             | passing            |
| ------------------ | ------------------ |
| instr\_timing      | :heavy_check_mark: |
| mem\_timing        | :heavy_check_mark: |
| mem\_timing-2      | :heavy_check_mark: |

| misc               | passing            |
| ------------------ | ------------------ |
| oam_bug causes     | :heavy_check_mark: |
| oam_bug non_causes | :heavy_check_mark: |
| oam_bug timing_bug | :heavy_check_mark: |


## Interface

### Supported graphics interfaces
* Null
* Linux framebuffer
* Bitmap (capture)

### Supported control interfaces
* Null
* Linux evdev

### Sound
(not implemented)


## License
All code is published under the BSD-3-Clause License. See [LICENSE](LICENSE)
for more information.
