# UTS TKBM262621 - Biomedical IC Design
## TM1638 LED & Key Display Module pada FPGA iCESugar V1.5

Project ini dibuat dari template
[oss-cad-suite-tcl-template](https://github.com/arumdapta98/oss-cad-suite-tcl-template)
(Windows + OSS CAD Suite + iCESugar V1.5 / iCE40UP5K).

## Fungsi

7-segment pada modul TM1638 menampilkan nilai **switch 8-bit** dalam bentuk
**hexadecimal** (blok kiri) dan **desimal** (blok kanan).

| switch (8 bit) | 7-segment kiri (hex) | 7-segment kanan (desimal) |
|---|---|---|
| `8'b10101010` | `AA` | `170` |
| `8'b11111111` | `FF` | `255` |

### Switch = 8 tombol pada modul TM1638

Board iCESugar hanya punya 4 DIP switch, sedangkan modul TM1638 punya 8 tombol
(S1..S8), sehingga 8 tombol tersebut dipakai sebagai switch 8-bit:

```
switch[7] = S1 (paling kiri)  ...  switch[0] = S8 (paling kanan)
```

* Mode default (`TOGGLE_MODE = 1`): setiap kali tombol ditekan, bit-nya
  **berubah (toggle)**, seperti switch biasa. LED1..LED8 menampilkan nilai
  bit S1..S8 (LED menyala = bit 1).
  Contoh: tekan S1, S3, S5, S7 -> `10101010` -> tampil `AA` dan `170`.
* `TOGGLE_MODE = 0`: switch = tombol yang sedang ditekan (tombol ditahan).

Tata letak 7-segment (digit 1 = paling kiri):

```
digit : 1 2 3 4 | 5 6 7 8
isi   :     H H |   D D D      H = hex (2 digit), D = desimal (nol di depan dikosongkan)
```

## Wiring (sesuai materi Hands on TM1638)

| TM1638 | iCESugar V1.5 | pin FPGA |
|---|---|---|
| VCC | PMOD1 pin 6 | - |
| GND | PMOD1 pin 5 | - |
| STB | PMOD1 pin 12 (P1_12) | 9 |
| CLK | PMOD1 pin 11 (P1_11) | 4 |
| DIO | PMOD1 pin 10 (P1_10) | 2 |

Clock 12 MHz on-board: pin 35. Constraint: `constraints/top_tm1638_demo.pcf`.

## Struktur direktori

```
tcl/top_tm1638_demo.v     top level: urutan perintah TM1638, switch, konversi hex/desimal
tcl/tm1638.v              driver serial TM1638 (STB/CLK/DIO)
tcl/top_tm1638_demo.tcl   skrip Yosys-Tcl (alternatif make syn)
constraints/              file pin (.pcf)
tb/top_tm1638_demo_tb.v   testbench (model TM1638 + penekanan tombol + pengecekan tampilan)
makefile                  syn / pnr / bit / all / flash / sim / clean
setenv.bat                set environment OSS CAD Suite (sesuaikan lokasi instalasi)
```

`rtl/top_blinky.v`, `tb/top_blinky_tb.v`, dan file blinky lain adalah bawaan
template dan tidak dipakai oleh project ini.

## Cara menjalankan

1. Edit `setenv.bat` sesuai lokasi OSS CAD Suite, lalu jalankan di **cmd**:
   ```
   setenv.bat
   ```
2. Simulasi (Icarus Verilog + GTKWave):
   ```
   make compile
   make vvp          :: cetak hasil pengecekan, akhir baris "ALL TESTS PASSED"
   make gtk          :: lihat waveform (build/top_tm1638_demo_tb.vcd)
   ```
   atau cukup `make sim`.
3. Synthesis, place & route, bitstream:
   ```
   make all
   ```
4. Program ke board (iCESugar, via `icesprog`):
   ```
   make flash
   ```
5. Bersihkan hasil build: `make clean`

## Video demo

Link video: https://drive.google.com/file/d/1SbYr0pPlomKO_-PGLfkC3F8QeXpLpKwR/view?usp=sharing

## Catatan

* Driver `tm1638.v` berasal dari
  [alangarf/tm1638-verilog](https://github.com/alangarf/tm1638-verilog),
  dengan satu perbaikan deklarasi (`output reg dio_out`) agar bisa dikompilasi
  oleh Icarus Verilog versi terbaru.
* `synth_ice40` dijalankan dengan `-noabc9` untuk menghindari crash internal
  yosys pada build Windows. Jika yosys masih crash (`write_xaiger2`), build dengan
  `make all SYNTH_FLAGS="-noabc9 -noabc"`.
* `tm1638.v`: `CLK_DIV` diubah dari 3 ke 4 agar lebar pulsa CLK (667 ns) memenuhi minimum TM1638 (400 ns)
  dan data tombol dibaca lebih lama setelah tepi turun CLK.
* Urutan langkah (`instruction_step`) kini kembali ke 0 secara eksplisit setelah langkah terakhir.
* Pembacaan tombol memakai jeda waktu sesuai datasheet TM1638 dan filter 3 sampel
  berturut-turut agar switch tidak berubah sendiri karena data tombol yang noisy.
* Parameter `TEST_FIXED = 1` pada `top_tm1638_demo.v` membuat switch tetap `8'hAA`
  (mengabaikan tombol), berguna untuk memeriksa tampilan saja.
* Parameter `TEST_KEYS = 1` menampilkan data tombol mentah (tanpa filter/toggle) untuk
  memeriksa pembacaan tombol: tanpa menyentuh tombol harus tampil `00` dan `0`.
