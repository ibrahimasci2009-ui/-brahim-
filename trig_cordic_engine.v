// ============================================================
// Trigonometri Hesaplama Motoru (CORDIC tabanlı) - Verilog
// Sinüs ve Kosinüs hesaplar. Iterative CORDIC.
// Bellek: atan sabitleri için küçük ROM içerir.
// Not: 10 milyar transistör pratik değildir. Bu modül ~binlerce
// transistör seviyesindedir. Büyük ölçek için çoklu instance
// veya büyük LUT bellek kullanılabilir.
// ============================================================

`timescale 1ns / 1ps

module trig_cordic_engine #(
    parameter WIDTH = 16,          // Veri genişliği (fixed-point)
    parameter ITERATIONS = 16      // CORDIC iterasyon sayısı
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                start,         // Hesaplamayı başlat
    input  wire signed [WIDTH-1:0] angle_in,  // Giriş açı (fixed-point, örn. pi/2 = 0x4000 gibi)
    output reg  signed [WIDTH-1:0] cos_out,
    output reg  signed [WIDTH-1:0] sin_out,
    output reg                 done
);

    // CORDIC kazancı için pre-scale (yaklaşık 0.607252935 * 2^(WIDTH-2) civarı)
    // Basitlik için başlangıç x = K_inv
    localparam signed [WIDTH-1:0] K_INV = 16'sd9949;  // ~0.60725 * 2^14 (WIDTH=16 için)

    // atan(2^-i) sabitleri (fixed-point, aynı ölçek)
    // Bu bir ROM / bellek gibi davranır
    reg signed [WIDTH-1:0] atan_lut [0:ITERATIONS-1];
    initial begin
        // WIDTH=16 için yaklaşık değerler (ölçek 2^14)
        atan_lut[0]  = 16'sd12868;  // atan(1)     ≈ 0.7854 * 16384
        atan_lut[1]  = 16'sd7596;   // atan(0.5)
        atan_lut[2]  = 16'sd4014;   // atan(0.25)
        atan_lut[3]  = 16'sd2037;
        atan_lut[4]  = 16'sd1023;
        atan_lut[5]  = 16'sd512;
        atan_lut[6]  = 16'sd256;
        atan_lut[7]  = 16'sd128;
        atan_lut[8]  = 16'sd64;
        atan_lut[9]  = 16'sd32;
        atan_lut[10] = 16'sd16;
        atan_lut[11] = 16'sd8;
        atan_lut[12] = 16'sd4;
        atan_lut[13] = 16'sd2;
        atan_lut[14] = 16'sd1;
        atan_lut[15] = 16'sd1;
    end

    // İç durum
    reg signed [WIDTH-1:0] x, y, z;
    reg [4:0] iter;
    reg busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x      <= 0;
            y      <= 0;
            z      <= 0;
            iter   <= 0;
            busy   <= 0;
            done   <= 0;
            cos_out <= 0;
            sin_out <= 0;
        end else begin
            done <= 0;
            if (start && !busy) begin
                // Başlangıç
                x    <= K_INV;
                y    <= 0;
                z    <= angle_in;
                iter <= 0;
                busy <= 1;
            end else if (busy) begin
                if (iter < ITERATIONS) begin
                    // CORDIC rotasyon adımı
                    if (z[WIDTH-1] == 1'b0) begin  // z >= 0, saat yönü tersi (pozitif)
                        x <= x - (y >>> iter);
                        y <= y + (x >>> iter);
                        z <= z - atan_lut[iter];
                    end else begin                 // z < 0, saat yönü
                        x <= x + (y >>> iter);
                        y <= y - (x >>> iter);
                        z <= z + atan_lut[iter];
                    end
                    iter <= iter + 1;
                end else begin
                    // Bitti
                    cos_out <= x;
                    sin_out <= y;
                    done    <= 1;
                    busy    <= 0;
                end
            end
        end
    end

endmodule

// ============================================================
// Basit Testbench (simülasyon için)
// ============================================================
module trig_cordic_tb;
    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg signed [15:0] angle;
    wire signed [15:0] cos, sin;
    wire done;

    trig_cordic_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .angle_in(angle),
        .cos_out(cos),
        .sin_out(sin),
        .done(done)
    );

    always #5 clk = ~clk;  // 100 MHz

    initial begin
        $dumpfile("trig_cordic.vcd");
        $dumpvars(0, trig_cordic_tb);

        rst_n = 0;
        #20;
        rst_n = 1;

        // Örnek: 0 derece (angle ≈ 0)
        angle = 16'sd0;
        start = 1;
        #10;
        start = 0;
        wait(done);
        $display("0 deg -> cos: %d, sin: %d", cos, sin);

        // Örnek: ~45 derece (pi/4 ≈ 0.7854 * 16384 ≈ 12868)
        #20;
        angle = 16'sd12868;
        start = 1;
        #10;
        start = 0;
        wait(done);
        $display("45 deg -> cos: %d, sin: %d", cos, sin);

        #50;
        $finish;
    end
endmodule
