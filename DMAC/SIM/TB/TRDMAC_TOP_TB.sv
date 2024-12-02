`define     IP_VER      32'h000
`define     SRC_ADDR    32'h100
`define     DST_ADDR    32'h104
`define     MAT_WIDTH   32'h108
`define     START       32'h10C
`define     DONE        32'h110

`define     TIMEOUT_CYCLE   4000000
module TRDMAC_TOP_TB ();

    reg                     clk;
    reg                     rst_n;

    bit [31:0]              origin_matrix[$];
    bit [31:0]              transpose_matrix[$];
    // clock generation
    initial begin
        clk                     = 1'b0;

        forever #10 clk         = !clk;
    end

    // reset generation
    initial begin
        rst_n                   = 1'b0;     // active at time 0

        repeat (3) @(posedge clk);          // after 3 cycles,
        rst_n                   = 1'b1;     // release the reset
    end

    //set random seed
    initial begin
        int seed = 12345;
        int random_value;
        random_value = $urandom(seed);
    end

    // enable waveform dump
    initial begin
        $dumpvars(0, u_DUT);
        $dumpfile("dump.vcd");
    end
	// timeout
	initial begin
		#`TIMEOUT_CYCLE $display("Timeout!");
		$finish;
	end

    APB                         apb_if  (.clk(clk));

    AXI_AW_CH                   aw_ch   (.clk(clk));
    AXI_W_CH                    w_ch    (.clk(clk));
    AXI_B_CH                    b_ch    (.clk(clk));
    AXI_AR_CH                   ar_ch   (.clk(clk));
    AXI_R_CH                    r_ch    (.clk(clk));

    task test_init();
        int data;
        apb_if.init();

        @(posedge rst_n);                   // wait for a release of the reset
        repeat (10) @(posedge clk);         // wait another 10 cycles

        apb_if.read(`IP_VER, data);
        $display("---------------------------------------------------");
        $display("IP version: %x", data);
        $display("---------------------------------------------------");

        $display("---------------------------------------------------");
        $display("SFRs Reset value test");
        apb_if.read(`SRC_ADDR, data);
        if (data===0)
            $display("TRDMAC_SRC_ADDR(pass): %x", data);
        else begin
            $display("TRDMAC_SRC_ADDR(fail): %x", data);
            @(posedge clk);
            $finish;
        end
        apb_if.read(`DST_ADDR, data);
        if (data===0)
            $display("TRDMAC_DST_ADDR(pass): %x", data);
        else begin
            $display("TRDMAC_DST_ADDR(fail): %x", data);
            @(posedge clk);
            $finish;
        end
        apb_if.read(`MAT_WIDTH, data);
        if (data===0)
            $display("TRDMAC_MAT_WIDTH(pass): %x", data);
        else begin
            $display("TRDMAC_MAT_WIDTH(fail): %x", data);
            @(posedge clk);
            $finish;
        end
        apb_if.read(`DONE, data);
        if (data===1)
            $display("TRDMAC_STATUS(pass): %x", data);
        else begin
            $display("TRDMAC_STATUS(fail): %x", data);
            @(posedge clk);
            $finish;
        end
        $display("---------------------------------------------------");
    endtask

    task gen_matrix(input int src_addr, input int mat_width);
        int word;
        for (int j = src_addr; j < (src_addr + (4*((mat_width)**2))); j = j + 4) begin
            word                = ($random) & ~('hFFFFF000);
            u_mem.write_word(j, word);
            origin_matrix.push_back(word);
        end
    endtask

    task start_dma(input int src_addr, input int dst_addr, input int mat_width, output time runtime);
        int data;
        realtime elapsed_time;

        $display("---------------------------------------------------");
        $display("Configuration test");
        apb_if.write(`SRC_ADDR, src_addr);
        apb_if.write(`DST_ADDR, dst_addr);
        apb_if.write(`MAT_WIDTH, mat_width);

        apb_if.read(`SRC_ADDR, data);
        if (data===src_addr)
            $display("TRDMAC_SRC_ADDR(pass): %x", data);
        else begin
            $display("TRDMAC_SRC_ADDR(fail): %x", data);
            @(posedge clk);
            $finish;
        end

        apb_if.read(`DST_ADDR, data);
        if (data===dst_addr)
            $display("TRDMAC_DST_ADDR(pass): %x", data);
        else begin
            $display("TRDMAC_DST_ADDR(fail): %x", data);
            @(posedge clk);
            $finish;
        end

        apb_if.read(`MAT_WIDTH, data);
        if (data===mat_width)
            $display("TRDMAC_MAT_WIDTH(pass): %x", data);
        else begin
            $display("TRDMAC_MAT_WIDTH(fail): %x", data);
            @(posedge clk);
            $finish;
        end

        $display("---------------------------------------------------");
        $display("DMA start");
        apb_if.write(`START, 32'h1);
        elapsed_time = $realtime;

        data = 0;
        while (data!=1) begin
            apb_if.read(`DONE, data);
            repeat (1) @(posedge clk); // Why??
        end
        @(posedge clk);
        elapsed_time = $realtime - elapsed_time;
        $timeformat(-9, 0, " ns", 10);

        $display("---------------------------------------------------");
        $display("DMA completed!");
        //$display("Elapsed time for DMA: %t", elapsed_time);
        $display("---------------------------------------------------");

        runtime = elapsed_time;
    endtask

    task check_result(input int dst_addr, input int mat_width, output int is_pass);
        $display("Compare Origin & Transpose Matrix");
        $display("---------------------------------------------------");
        for (int j = dst_addr; j < dst_addr + (4*((mat_width)**2)); j = j + 4) begin
            transpose_matrix.push_back(u_mem.read_word(j));
        end

        $display("Origin Matrix:");
        foreach (origin_matrix[i]) begin
            if (i % mat_width == 0 && i != 0) $display(""); 
            $write("%4d ", origin_matrix[i]); 
        end
        $display(""); 
        $display("");
        $display("Transpose Matrix:");
        foreach (transpose_matrix[i]) begin
            if (i % mat_width == 0 && i != 0) $display(""); 
            $write("%4d ", transpose_matrix[i]); 
        end
        $display("");
        $display("");

        for (int i = 0; i < mat_width; i++) begin
            for (int j = 0; j < mat_width; j++) begin
                if (origin_matrix[(i*mat_width)+j] != transpose_matrix[(j*mat_width)+i]) begin
                    $display("Error: origin_matrix[%0d][%0d] != transpose_matrix[%0d][%0d] | MissMatch!",i,j,j,i);
                    is_pass = 0;
                    //$finish;
                end
            end
        end
        
        origin_matrix.delete();
        transpose_matrix.delete();
        is_pass = 1;
    endtask
    
    int src_addr;
    int dst_addr;
    int mat_width;

    int testcase1_pass = 0;
    int testcase2_pass = 0;
    int testcase3_pass = 0;
    int testcase4_pass = 0;
    time time_0, time_1;

    // main
    initial begin
        test_init();

        src_addr        = 'h0000_0100;
        dst_addr        = 'h0000_A000;
        mat_width       = 32;
        $display("===================================================");
        $display(" TestCase 1 | MAT_WIDTH = 32"); 
        $display("===================================================");
        gen_matrix(src_addr, mat_width);
        start_dma(src_addr, dst_addr, mat_width, time_0);
        check_result(dst_addr, mat_width, testcase1_pass);
        if(testcase1_pass == 1) begin
            $display("TestCase 1 Pass!");
            $display("<< TestCase 1's Execution Time: %d (ns)", time_0);
        end else begin
            $display("TestCase 1 Fail!");
        end
        $display("");

        src_addr        = 'h0000_0100;
        dst_addr        = 'h0000_A000;
        mat_width       = 16;
        $display("===================================================");
        $display(" TestCase 2 | MAT_WIDTH = 16"); 
        $display("===================================================");
        gen_matrix(src_addr, mat_width);
        start_dma(src_addr, dst_addr, mat_width, time_1);
        check_result(dst_addr, mat_width, testcase2_pass);
        if(testcase2_pass == 1) begin
            $display("TestCase 2 Pass!");
        end else begin
            $display("TestCase 2 Fail!");
        end
        $display("");

        src_addr        = 'h0000_0000;
        dst_addr        = 'h0000_0A00;
        mat_width       = 8;
        $display("===================================================");
        $display(" TestCase 3 | MAT_WIDTH = 8"); 
        $display("===================================================");
        gen_matrix(src_addr, mat_width);
        start_dma(src_addr, dst_addr, mat_width, time_1);
        check_result(dst_addr, mat_width, testcase3_pass);
        if(testcase3_pass == 1) begin
            $display("TestCase 3 Pass!");
        end else begin
            $display("TestCase 3 Fail!");
        end
        $display("");

        src_addr        = 'h0000_0000;
        dst_addr        = 'h0000_A000;
        mat_width       = 4;
        $display("===================================================");
        $display(" TestCase 4 | MAT_WIDTH = 4"); 
        $display("===================================================");
        gen_matrix(src_addr, mat_width);
        start_dma(src_addr, dst_addr, mat_width, time_1);
        check_result(dst_addr, mat_width, testcase4_pass);
        if(testcase4_pass == 1) begin
            $display("TestCase 4 Pass!");
        end else begin
            $display("TestCase 4 Fail!");
        end;

        $display("");
        $display("===================================================");
        $display(" Total Result"); 
        $display("===================================================");
        if(testcase1_pass == 1) begin
            $display("TestCase 1 Pass!");
        end else begin
            $display("TestCase 1 Fail!");
        end
        if(testcase2_pass == 1) begin
            $display("TestCase 2 Pass!");
        end else begin
            $display("TestCase 2 Fail!");
        end
        if(testcase3_pass == 1) begin
            $display("TestCase 3 Pass!");
        end else begin
            $display("TestCase 3 Fail!");
        end
        if(testcase4_pass == 1) begin
            $display("TestCase 4 Pass!");
        end else begin
            $display("TestCase 4 Fail!");
        end

        $display("<< TestCase 1's Execution Time: %d (ns)", time_0);
        $display("===================================================");
        $display("");
        $finish;
    end

    AXI_SLAVE   u_mem (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .aw_ch                  (aw_ch),
        .w_ch                   (w_ch),
        .b_ch                   (b_ch),
        .ar_ch                  (ar_ch),
        .r_ch                   (r_ch)
    );

    TRDMAC_TOP  u_DUT (
        .clk                    (clk),
        .rst_n                  (rst_n),

        // APB interface
        .psel_i                 (apb_if.psel),
        .penable_i              (apb_if.penable),
        .paddr_i                (apb_if.paddr[11:0]),
        .pwrite_i               (apb_if.pwrite),
        .pwdata_i               (apb_if.pwdata),
        .pready_o               (apb_if.pready),
        .prdata_o               (apb_if.prdata),
        .pslverr_o              (apb_if.pslverr),

        // AXI AW channel
        .awid_o                 (aw_ch.awid),
        .awaddr_o               (aw_ch.awaddr),
        .awlen_o                (aw_ch.awlen),
        .awsize_o               (aw_ch.awsize),
        .awburst_o              (aw_ch.awburst),
        .awvalid_o              (aw_ch.awvalid),
        .awready_i              (aw_ch.awready),

        // AXI W channel
        .wid_o                  (w_ch.wid),
        .wdata_o                (w_ch.wdata),
        .wstrb_o                (w_ch.wstrb),
        .wlast_o                (w_ch.wlast),
        .wvalid_o               (w_ch.wvalid),
        .wready_i               (w_ch.wready),

        // AXI B channel
        .bid_i                  (b_ch.bid),
        .bresp_i                (b_ch.bresp),
        .bvalid_i               (b_ch.bvalid),
        .bready_o               (b_ch.bready),

        // AXI AR channel
        .arid_o                 (ar_ch.arid),
        .araddr_o               (ar_ch.araddr),
        .arlen_o                (ar_ch.arlen),
        .arsize_o               (ar_ch.arsize),
        .arburst_o              (ar_ch.arburst),
        .arvalid_o              (ar_ch.arvalid),
        .arready_i              (ar_ch.arready),

        // AXI R channel
        .rid_i                  (r_ch.rid),
        .rdata_i                (r_ch.rdata),
        .rresp_i                (r_ch.rresp),
        .rlast_i                (r_ch.rlast),
        .rvalid_i               (r_ch.rvalid),
        .rready_o               (r_ch.rready)
    );

endmodule
