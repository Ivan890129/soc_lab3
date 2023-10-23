`timescale 1ns / 1ps
module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  reg                      rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 
    input   wire                     sm_tready, 
    output  reg                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  reg  [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire  [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
begin




    // write your code here!
//---------------------------------------------------------------------
//   PARAMETER
//---------------------------------------------------------------------
parameter S_Idle  = 4'd0 ;
parameter S_addr  = 4'd1 ;
parameter S_write = 4'd2 ;
parameter S_readxin   = 4'd3; 
parameter S_cal   = 4'd4; 
parameter S_done =4'd5;
//---------------------------------------------------------------------
//   WIRE AND REG DECLARATION
//---------------------------------------------------------------------
reg [3:0] cs, ns ; 
 reg [(pDATA_WIDTH-1):0] y;
 reg [(pDATA_WIDTH-1):0] data_length;
 reg [2:0] ap;
 reg last_out;
//==============================================//
//                 axi              
//==============================================//
reg [(pADDR_WIDTH-1):0] awaddr_reg,araddr_reg;

reg raddr_valid;
always@(posedge axis_clk or negedge axis_rst_n)begin 
    if(!axis_rst_n)
        awaddr_reg <= 0;
    else 
        if(awready)
            awaddr_reg <= awaddr;
end 

always@(posedge axis_clk or negedge axis_rst_n)begin 
    if(!axis_rst_n)
        araddr_reg <= 0;
    else 
        if(arready)
            araddr_reg <= araddr;
end 

assign awready = (cs == S_addr)?1:0;
assign wready = (cs == S_write)?1:0;
assign arready = ~raddr_valid;
assign rdata = (awaddr_reg == 0)?{{29{1'b0}},ap[2:0]}:tap_Do ;                ////////// address == 0x00 need modify


always@(posedge axis_clk )begin 
    if(rvalid)
        rvalid <= 0;
    else
        rvalid <= (rready && raddr_valid)?1:0 ;
end


always@(posedge axis_clk or negedge axis_rst_n)begin 
    if(!axis_rst_n)
         raddr_valid <=0;
    else 
        if(arready && arvalid)
            raddr_valid <= 1;
        else if(rvalid)   
            raddr_valid <=  0;
end

/// data_length //
always@(posedge axis_clk or negedge axis_rst_n )begin 
    if(!axis_rst_n)
        data_length <= 0;
    else 
        if((awaddr_reg == 12'h10)&&wvalid &&wready)
            data_length <= wdata;
end 
// ap.start idle done // // ap[0]-start    ap[1]-done    ap[2]-idle
always@(posedge axis_clk or negedge axis_rst_n )begin  
    if(!axis_rst_n)
        ap[2:0] <= 3'b100; //set idle = 1
    else 
        if((awaddr_reg == 12'h00) &&wvalid &&wready&& ap[2])//ap start //ap[2]idle=1 start is valid
            ap[2:0] <= wdata[2:0];
        else if (ap[0]) 
            ap <= ap&(3'b000);  //when sample ap-start set idle to 0
        else if (ns==S_done)    //ap[1] done  ap[2]idle
            ap <=  ap|3'b110;
        else if(ns == S_Idle) // ap[1] done is transfer to tb 
            ap <=ap &3'b101;
        else 
            ap <= ap;
end       

// ap.start idle done // 
always@(posedge axis_clk or negedge axis_rst_n )begin 
    if(!axis_rst_n)
        last_out <= 0;
    else 
        if((ss_tlast) &&(ss_tready)&&(ss_tvalid))
            last_out<= 1;
        else 
            last_out <= last_out;
end   
//==============================================//
//                bram coeff  (tap)            //
//==============================================//

wire [(pADDR_WIDTH-1):0] addr_tap;
reg  [(pADDR_WIDTH-1):0] tap_rdptr;
assign addr_tap = ((cs==S_readxin)||(cs==S_cal))?tap_rdptr:
                   (wvalid)? awaddr_reg: araddr_reg;
always@(*)begin 
    case(addr_tap)
        12'h20: tap_A = 12'h0;  //0
        12'h24: tap_A = 12'h4;  //1
        12'h28: tap_A = 12'h8;  //2
        12'h2c: tap_A = 12'hc;  //3
        12'h30: tap_A = 12'h10; //4
        12'h34: tap_A = 12'h14; //5
        12'h38: tap_A = 12'h18; //6
        12'h3c: tap_A = 12'h1c; //7
        12'h40: tap_A = 12'h20; //8
        12'h44: tap_A = 12'h24; //9
        12'h48: tap_A = 12'h28; //10
    default : tap_A = 12'hfff;//not write in tap bram
    endcase
end 

assign tap_WE = (wvalid && (cs== S_write) &&!(&tap_A))?4'hf:4'd0;
assign tap_Di = wdata;
assign tap_EN = 1;

always@(posedge axis_clk or negedge axis_rst_n)begin 
    if(!axis_rst_n)
        tap_rdptr <= 0;
    else
        if(ns==S_readxin)
            tap_rdptr <=  12'h48;
        else if((ns == S_cal)&&(cs == S_readxin))
            tap_rdptr <= 12'h20;
        else 
            tap_rdptr <= tap_rdptr+4; // +4 only need in cs == S_cal
end 
//==============================================//
//                bram xin                    //
//==============================================//
assign data_Di = (cs == S_readxin)?ss_tdata:0 ; 
assign data_EN = 1;
assign data_WE = ((cs == S_readxin)||(cs == S_addr)||(cs == S_write ))?4'hf:0; //read xin from stream and write in bram  
reg [(pADDR_WIDTH-1):0] data_wrptr ,data_rdptr;

 wire  [(pADDR_WIDTH-1):0] data_next_wrpt = (data_wrptr== (Tape_Num-1)*4)? 0:data_wrptr+4; //data_wrptr and rdpt +4 can combine 
 wire  [(pADDR_WIDTH-1):0] data_next_rdpt = (data_rdptr== (Tape_Num-1)*4)? 0:data_rdptr+4; //data_wrptr and rdpt +4 can combine 

wire [(pADDR_WIDTH-1):0]c_ptr = ((cs == S_addr)||(cs == S_write )||(cs == S_readxin))?data_wrptr:data_rdptr;
reg [(pADDR_WIDTH-1):0]nxt_ptr;
always@(*)begin 
    case(c_ptr)
        0: nxt_ptr = 4;//0
        4: nxt_ptr = 8;//1
        8: nxt_ptr = 12;//2
        12: nxt_ptr = 16;//3
        16: nxt_ptr = 20;//4
        20: nxt_ptr = 24;//5
        24: nxt_ptr = 28;//6
        28: nxt_ptr = 32;//7
        32: nxt_ptr = 36;//8
        36: nxt_ptr = 40;//9
        40: nxt_ptr =0;//10
    default : nxt_ptr = 0;
    endcase
end 

always@(posedge axis_clk or negedge axis_rst_n)begin 
    if(!axis_rst_n)
        data_wrptr <= 0;
    else 
        if((cs == S_addr)||(cs == S_write ))
            data_wrptr <= (ns == S_readxin)? 0:nxt_ptr; // data_A == 11(data_Num)
        else 
            data_wrptr <= (cs ==S_readxin)? nxt_ptr:data_wrptr;
end 

assign data_A = (cs==S_cal)?data_rdptr:data_wrptr;
always@(posedge axis_clk or negedge axis_rst_n)begin 
    if(!axis_rst_n)
        data_rdptr <= 0;
    else 
        if(cs == S_readxin)
            data_rdptr <= nxt_ptr;
        else 
           if(cs == S_cal)
                data_rdptr <= nxt_ptr ;
            else 
                data_rdptr <= 'dz;  //'dz debug 
end 
        
        
//==============================================//
//               ss stream  (xin )            //
//==============================================//
assign ss_tready = (cs == S_readxin)?1:0;

 //==============================================//
//               sm stream  (y out )            //
//==============================================//
always@(posedge axis_clk )begin 
    sm_tvalid <= ((cs == S_cal)&&(ns == S_readxin))?1:0;
end 
assign sm_tdata = y;
//==============================================//
//               output y            //
//==============================================//


always@(posedge axis_clk or negedge axis_rst_n)begin 
    if(!axis_rst_n)
        y <=0 ;
    else 
        if(cs == S_cal)
            y <= tap_Do*data_Do+y;
        else 
            y <= 0;
end 



//==============================================//
//                  cs                          //
//==============================================//
always @(posedge axis_clk or negedge axis_rst_n)begin 
    if(!axis_rst_n)
        cs <= S_Idle;
    else 
        cs <= ns;
end 
// ns // 
always@(*)begin 
    case (cs)
        S_Idle: ns = S_addr;
        S_addr: ns = (awvalid)?S_write:S_addr;
        S_write: ns = (wvalid)?
                      ((awaddr_reg==12'h00 && wdata[0])? S_readxin:S_addr):
                      S_write;
        S_readxin: ns = (sm_tvalid && last_out)?S_done:
                                (ss_tvalid)? S_cal:S_readxin;
        S_cal : ns = (nxt_ptr == data_wrptr)?S_readxin: S_cal;
        //S_done: ns  = S_done;
         S_done :ns = ((araddr_reg == 12'h00)&&(rready&&rvalid))?S_Idle: S_done;
       default: ns = S_cal;               
    endcase
end 


end

endmodule