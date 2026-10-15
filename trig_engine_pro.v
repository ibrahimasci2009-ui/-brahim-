// ============================================================
// Profesyonel 32-bit Trigonometri Motoru
// - Güçlü çok döngülü signed bölücü (restoring-style)
// - Daha büyük ve düzenli bellek (atan LUT + ek sabitler)
// Fonksiyonlar: sin, cos, tan, cot, sec, csc
// ============================================================

`timescale 1ns / 1ps

module trig_engine_pro #(
    parameter WIDTH = 32,
    parameter ITERATIONS = 32,
    parameter DIV_ITER = 32          // Bölme iterasyon sayısı
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire [2:0]               func_sel,   // 0=sin 1=cos 2=tan 3=cot 4=sec 5=csc 6=sin&cos
    input  wire signed [WIDTH-1:0]  angle_in,
    output reg  signed [WIDTH-1:0]  result_out,
    output reg  signed [WIDTH-1:0]  result_out2,
    output reg                      done,
    output reg                      error
);

    // ---------- Büyük Bellek (ROM) ----------
    // 1) CORDIC atan tablosu (daha hassas)
    // 2) Ek sabitler (1.0 ölçekli değerler)
    reg signed [WIDTH-1:0] atan_lut [0:ITERATIONS-1];
    reg signed [WIDTH-1:0] const_mem [0:7];   // Ek bellek

    initial begin
        // atan(2^-i)  (ölçek ≈ 2^30)
        atan_lut[0]  = 32'sd843314857;
        atan_lut[1]  = 32'sd497837829;
        atan_lut[2]  = 32'sd263043836;
        atan_lut[3]  = 32'sd133525159;
        atan_lut[4]  = 32'sd67021687;
        atan_lut[5]  = 32'sd33543516;
        atan_lut[6]  = 32'sd16775851;
        atan_lut[7]  = 32'sd8389253;
        atan_lut[8]  = 32'sd4194670;
        atan_lut[9]  = 32'sd2097336;
        atan_lut[10] = 32'sd1048668;
        atan_lut[11] = 32'sd524334;
        atan_lut[12] = 32'sd262167;
        atan_lut[13] = 32'sd131083;
        atan_lut[14] = 32'sd65542;
        atan_lut[15] = 32'sd32771;
        atan_lut[16] = 32'sd16385;
        atan_lut[17] = 32'sd8193;
        atan_lut[18] = 32'sd4096;
        atan_lut[19] = 32'sd2048;
        atan_lut[20] = 32'sd1024;
        atan_lut[21] = 32'sd512;
        atan_lut[22] = 32'sd256;
        atan_lut[23] = 32'sd128;
        atan_lut[24] = 32'sd64;
        atan_lut[25] = 32'sd32;
        atan_lut[26] = 32'sd16;
        atan_lut[27] = 32'sd8;
        atan_lut[28] = 32'sd4;
        atan_lut[29] = 32'sd2;
        atan_lut[30] = 32'sd1;
        atan_lut[31] = 32'sd0;

        // Ek sabit bellek
        const_mem[0] = 32'sd1073741824;  // 1.0 * 2^30
        const_mem[1] = 32'sd652032874;   // K^-1
        const_mem[2] = 32'sd843314857;   // pi/4
        const_mem[3] = 32'sd1686629713;  // pi/2
        const_mem[4] = 32'sd3373259426;  // pi
        const_mem[5] = 32'sd0;
        const_mem[6] = 32'sd0;
        const_mem[7] = 32'sd0;
    end

    localparam signed [WIDTH-1:0] K_INV = 32'sd652032874;

    // ---------- CORDIC durumu ----------
    reg signed [WIDTH-1:0] x, y, z;
    reg [5:0] iter;
    reg busy;
    reg [2:0] func_latched;

    // ---------- Profesyonel Bölücü ----------
    reg signed [WIDTH-1:0] div_num, div_den;
    reg signed [WIDTH:0]   div_rem;      // remainder (1 bit geniş)
    reg signed [WIDTH-1:0] div_quot;
    reg [5:0] div_count;
    reg div_busy;
    reg div_sign;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 0; y <= 0; z <= 0;
            iter <= 0; busy <= 0;
            done <= 0; error <= 0;
            result_out <= 0; result_out2 <= 0;
            div_busy <= 0;
            div_count <= 0;
        end else begin
            done <= 0;

            // CORDIC başlat
            if (start && !busy && !div_busy) begin
                x <= K_INV;
                y <= 0;
                z <= angle_in;
                iter <= 0;
                busy <= 1;
                func_latched <= func_sel;
                error <= 0;
            end
            // CORDIC döngüsü
            else if (busy) begin
                if (iter < ITERATIONS) begin
                    if (z[WIDTH-1] == 1'b0) begin
                        x <= x - (y >>> iter);
                        y <= y + (x >>> iter);
                        z <= z - atan_lut[iter];
                    end else begin
                        x <= x + (y >>> iter);
                        y <= y - (x >>> iter);
                        z <= z + atan_lut[iter];
                    end
                    iter <= iter + 1;
                end else begin
                    busy <= 0;
                    case (func_latched)
                        3'd0: begin result_out <= y; done <= 1; end
                        3'd1: begin result_out <= x; done <= 1; end
                        3'd2: begin // tan
                            if (x == 0) begin error <= 1; done <= 1; end
                            else start_div(y, x);
                        end
                        3'd3: begin // cot
                            if (y == 0) begin error <= 1; done <= 1; end
                            else start_div(x, y);
                        end
                        3'd4: begin // sec
                            if (x == 0) begin error <= 1; done <= 1; end
                            else start_div(const_mem[0], x);
                        end
                        3'd5: begin // csc
                            if (y == 0) begin error <= 1; done <= 1; end
                            else start_div(const_mem[0], y);
                        end
                        3'd6: begin
                            result_out <= y; result_out2 <= x; done <= 1;
                        end
                        default: begin result_out <= y; done <= 1; end
                    endcase
                end
            end
            // Güçlü bölücü (çok döngülü)
            else if (div_busy) begin
                if (div_count < DIV_ITER) begin
                    // Restoring-style adım
                    div_rem = (div_rem << 1) | div_num[WIDTH-1];
                    div_num <= div_num << 1;

                    if (div_sign) begin
                        if (div_rem >= 0)
                            div_rem = div_rem - div_den;
                        else
                            div_rem = div_rem + div_den;
                    end else begin
                        if (div_rem >= div_den)
                            div_rem = div_rem - div_den;
                        else
                            div_rem = div_rem;
                    end

                    div_quot <= (div_quot << 1) | (div_rem[WIDTH] ? 1'b0 : 1'b1);
                    div_count <= div_count + 1;
                end else begin
                    // İşaret düzeltmesi
                    if (div_sign)
                        result_out <= -div_quot;
                    else
                        result_out <= div_quot;
                    done <= 1;
                    div_busy <= 0;
                end
            end
        end
    end

    // Bölücü başlatma görevi (task)
    task start_div;
        input signed [WIDTH-1:0] num;
        input signed [WIDTH-1:0] den;
        begin
            div_sign <= num[WIDTH-1] ^ den[WIDTH-1];
            div_num  <= num[WIDTH-1] ? -num : num;
            div_den  <= den[WIDTH-1] ? -den : den;
            div_rem  <= 0;
            div_quot <= 0;
            div_count <= 0;
            div_busy <= 1;
        end
    endtask

endmodule

// ============================================================
// Testbench
// ============================================================
module trig_engine_pro_tb;
    reg clk = 0, rst_n = 0, start = 0;
    reg [2:0] func_sel;
    reg signed [31:0] angle;
    wire signed [31:0] result, result2;
    wire done, error;

    trig_engine_pro dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .func_sel(func_sel), .angle_in(angle),
        .result_out(result), .result_out2(result2),
        .done(done), .error(error)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("trig_pro.vcd");
        $dumpvars(0, trig_engine_pro_tb);

        rst_n = 0; #30; rst_n = 1;

        // Testler
        func_sel = 0; angle = 0; start = 1; #10; start = 0;
        wait(done); $display("sin(0) = %d", result);

        #50; func_sel = 2; angle = 843314857; start = 1; #10; start = 0;
        wait(done); $display("tan(45) = %d  error=%b", result, error);

        #50; func_sel = 4; angle = 843314857; start = 1; #10; start = 0;
        wait(done); $display("sec(45) = %d  error=%b", result, error);

        #50; func_sel = 5; angle = 500000000; start = 1; #10; start = 0;
        wait(done); $display("csc(...) = %d error=%b", result, error);

        #200; $finish;
    end
endmodule
