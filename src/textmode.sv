// Text mode generator for VGA.

module top_textmode (
    input  wire logic clk_100m,     // 100 MHz clock
    input  wire logic btn_rst_n,    // reset button
    output      logic vga_hsync,    // VGA horizontal sync
    output      logic vga_vsync,    // VGA vertical sync
    output      logic [3:0] vga_r,  // 4-bit VGA red
    output      logic [3:0] vga_g,  // 4-bit VGA green
    output      logic [3:0] vga_b   // 4-bit VGA blue
    );

    // generate pixel clock
    logic clk_pix;
    logic clk_pix_locked;
    clock_480p clock_pix_inst (
       .clk_100m,
       .rst(!btn_rst_n),  // reset button is active low
       .clk_pix,
       .clk_pix_5x(),  // not used for VGA output
       .clk_pix_locked
    );
    
    // generate system clock
    logic clk_sys;
    logic clk_sys_locked;
    logic rst_sys;
    clock_sys clock_sys_inst (
        .clk_100m,
        .rst(!btn_rst_n),  // reset button is active low
        .clk_sys,
        .clk_sys_locked
    );
    always_ff @(posedge clk_sys) rst_sys <= !clk_sys_locked;  // wait for clock lock

    // display sync signals and coordinates
    localparam CORDW = 16;  // screen coordinate width in bits
    logic signed [CORDW-1:0] sx, sy;
    logic signed hsync, vsync, de;
    logic newline;
    logic newframe;
    display_480p display_inst (
        .clk_pix,
        .rst_pix(!clk_pix_locked),  // wait for clock lock
        .hsync,
        .vsync,
        .de,
        .frame(newframe),
        .line(newline),
        .sx,
        .sy
    );

    // Deal with output latency
    localparam earlyf = 3;
    logic signed [CORDW-1:0] fsx;
    always_comb begin
        fsx = sx+earlyf;
    end

    // Transfer newline signal from pixel to system domains.
    logic newline_sys;
    xd xd_newline (
        .clk_src(clk_pix),
        .clk_dst(clk_sys),
        .flag_src(newline),
        .flag_dst(newline_sys)
    );

    // Transfer newframe signal from pixel to system domains.
    logic newframe_sys;
    xd xd_newframe (
        .clk_src(clk_pix),
        .clk_dst(clk_sys),
        .flag_src(newframe),
        .flag_dst(newframe_sys)
    );
    
    // The is 96 8x8 character images (code 32..127).
    localparam PM_IMAGE = "charset.mem";
    localparam PM_CWIDTH = 8;
    localparam PM_MEXTENT = 96*8;
    localparam PM_ADDRW = $clog2(PM_MEXTENT);
    logic [PM_ADDRW-1:0] pm_addr_read;
    logic [PM_CWIDTH-1:0] pm_pix_read;
    bram_sdp #(
        .WIDTH(PM_CWIDTH),
        .DEPTH(PM_MEXTENT),
        .INIT_F(PM_IMAGE)
    ) bram_pm_inst (
        .clk_write(clk_sys),
        .clk_read(clk_sys),
        .we(),
        .addr_write(),
        .addr_read(pm_addr_read),
        .data_in(),
        .data_out(pm_pix_read)
    );
    
    // Character array is in memory.
    localparam CM_MESSAGE = "message.mem";
    localparam CM_CWIDTH = 8;
    localparam CM_MEXTENT = 80*30;
    localparam CM_ADDRW = $clog2(CM_MEXTENT);
    logic [CM_ADDRW-1:0] cm_addr_read;
    logic [CM_CWIDTH-1:0] cm_char_read;
    bram_sdp #(
        .WIDTH(CM_CWIDTH),
        .DEPTH(CM_MEXTENT),
        .INIT_F(CM_MESSAGE)
    ) bram_cm_inst (
        .clk_write(clk_sys),
        .clk_read(clk_sys),
        .we(),
        .addr_write(),
        .addr_read(cm_addr_read),
        .data_in(),
        .data_out(cm_char_read)
    );

    // paint colour: white inside square, blue outside
    logic [3:0] paint_r, paint_g, paint_b;
    logic pixel;
    always_comb begin
        paint_r = (pixel) ? 4'b0 : 1;
        paint_g = (pixel) ? 4'b0 : 3+sx[9:6];
        paint_b = (pixel) ? 4'b0 : 7+sy[9:6];
    end

    // display colour: paint colour but black in blanking interval
    logic [3:0] display_r, display_g, display_b;
    always_comb begin
        display_r = (de) ? paint_r : 4'h0;
        display_g = (de) ? paint_g : 4'h0;
        display_b = (de) ? paint_b : 4'h0;
    end
    
    // VGA Pmod output
    always_ff @(posedge clk_pix) begin
        vga_hsync <= hsync;
        vga_vsync <= vsync;
        vga_r <= display_r;
        vga_g <= display_g;
        vga_b <= display_b;
    end
    
    // Shared linebuffer
    logic lb_pix_out;
    logic lb_pix_in;
    localparam LB_MEXTENT = 640;
    localparam LB_ADDRW = $clog2(LB_MEXTENT);
    logic [LB_ADDRW-1:0] lb_write_addr;
    logic [LB_ADDRW-1:0] write_addr;
    logic [LB_ADDRW-1:0] lb_read_addr;
    bram_sdp #(
        .WIDTH(1),
        .DEPTH(LB_MEXTENT),
        .INIT_F("stripes.mem")
        ) bram_lb (
        .clk_write(clk_sys),
        .clk_read(clk_pix),
        .we(1),
        .addr_write(lb_write_addr),
        .addr_read(lb_read_addr),
        .data_in(lb_pix_in),
        .data_out(lb_pix_out)
    );
    
    // Read out of the line buffer in pixel clock domain, setting the
    // address on pixel in advance using fsx instead of sx to trigger.
    always_ff @(posedge clk_pix) begin
        lb_read_addr <= fsx;
        pixel <= lb_pix_out;
    end
    
    logic [10:0] line_srcline = 0;
    
    logic [7:0] currpix;
    
    localparam writefudge=16;
    enum { CHARREAD, COPYPIX, PIXREAD, W1, W2, W3, W4, W5, W6, W7, W8 } line_copystage, next_copystage;    
    always_ff @(posedge clk_sys) begin
        if( write_addr<(640+writefudge) ) begin
            case( line_copystage )
                CHARREAD: begin cm_addr_read = (line_srcline[10:4]<<6)+(line_srcline[10:4]<<4)+write_addr[LB_ADDRW-1:3]; line_copystage<=PIXREAD; end
                PIXREAD: begin pm_addr_read <= {cm_char_read-32,line_srcline[3:1]}; line_copystage<=COPYPIX; end
                COPYPIX: begin currpix <= pm_pix_read; line_copystage<=W1; end
                W1: begin lb_write_addr<=write_addr-writefudge; write_addr<=write_addr+1; lb_pix_in <= currpix[7]; line_copystage<=W2; end
                W2: begin lb_write_addr<=write_addr-writefudge; write_addr<=write_addr+1; lb_pix_in <= currpix[6]; line_copystage<=W3; end
                W3: begin lb_write_addr<=write_addr-writefudge; write_addr<=write_addr+1; lb_pix_in <= currpix[5]; line_copystage<=W4; end
                W4: begin lb_write_addr<=write_addr-writefudge; write_addr<=write_addr+1; lb_pix_in <= currpix[4]; line_copystage<=W5; end
                W5: begin lb_write_addr<=write_addr-writefudge; write_addr<=write_addr+1; lb_pix_in <= currpix[3]; line_copystage<=W6; end
                W6: begin lb_write_addr<=write_addr-writefudge; write_addr<=write_addr+1; lb_pix_in <= currpix[2]; line_copystage<=W7; end
                W7: begin lb_write_addr<=write_addr-writefudge; write_addr<=write_addr+1; lb_pix_in <= currpix[1]; line_copystage<=W8; end
                W8: begin lb_write_addr<=write_addr-writefudge; write_addr<=write_addr+1; lb_pix_in <= currpix[0]; line_copystage<=CHARREAD; end
                //end
            endcase
        end
        if( newline_sys && sy>=0 ) begin
            write_addr <= 0;
            line_copystage <= CHARREAD;
            line_srcline <= sy;
        end
    end
    
endmodule
