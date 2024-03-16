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

    // display sync signals and coordinates
    localparam CORDW = 10;  // screen coordinate width in bits
    logic [CORDW-1:0] sx, sy;
    logic hsync, vsync, de;
    simple_480p display_inst (
        .clk_pix,
        .rst_pix(!clk_pix_locked),  // wait for clock lock
        .sx,
        .sy,
        .hsync,
        .vsync,
        .de
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
        .clk_write(clk_pix),
        .clk_read(clk_pix),
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
        .clk_write(clk_pix),
        .clk_read(clk_pix),
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


    logic [7:0] currpix;    // Pixels being streamed out
    logic [7:0] readypix;   // Pixels ready when currpix runs out
    logic [CM_CWIDTH-1:0] charaddr;  // Pointer into the characer matrix.
    logic [7:0] nextchar;   // Character read from character matrix.
    logic [PM_ADDRW-1:0] pixaddr;   // Address of pixels.

    always_ff @(posedge clk_pix) begin
        if( sy<480 && sx<640 ) begin
            case( sx[2:0] )
                0: begin
                    //currpix <= 8'h55;
                    currpix <= readypix;
                    cm_addr_read <= charaddr;
                end
                1: begin
                    charaddr <= charaddr+1;
                    //charaddr = sx[9:3];
                end
                2: begin
                    nextchar <= cm_char_read;
                    //nextchar <= 32+sx[8:3];
                end
                3: begin
                    pixaddr <= ((nextchar-32)<<3)+sy[3:1];
                end
                4: begin
                    pm_addr_read <= pixaddr;
                end
                5: begin
                    readypix <= pm_pix_read;
                end
                default: begin
                end
            endcase
            //if( sx[2:0]==0 ) begin
            //    pixel <= readypix[7];
            //end else begin
                pixel <= currpix[3'd7-sx[2:0]];
            //end
        end else begin
            //if( sy==480 && sx==0 ) begin
            //    charaddr <= 0;
            //end
            if( sy[3:1]!=7 && sy<480 && sx==640 ) begin
                charaddr <= charaddr-80;
            end
        end
    end


endmodule
