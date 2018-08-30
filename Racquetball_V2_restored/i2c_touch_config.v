 
 module  i2c_touch_config(
               //Host Side
               iCLK,
               iRSTN,
               oREADY,
               INT_n,
               oREG_X1,
               oREG_Y1,
               oREG_X2,
               oREG_Y2,
               oREG_X3,
               oREG_Y3,
               oREG_X4,
               oREG_Y4,
               oREG_X5,
               oREG_Y5,
               oREG_GESTURE,
               oREG_TOUCH_COUNT,
               //I2C Side
               I2C_SDAT,
               I2C_SCLK

 ); 

	input         iCLK;     // master clock input
	input         iRSTN;       // asynchronous reset
   
	output reg [9:0] oREG_X1,oREG_X2,oREG_X3,oREG_X4,oREG_X5;
	output reg [8:0] oREG_Y1,oREG_Y2,oREG_Y3,oREG_Y4,oREG_Y5;
	
	output reg [7:0] oREG_GESTURE;
	output reg [3:0] oREG_TOUCH_COUNT;
	output  reg   oREADY;

	input         INT_n;
   output        I2C_SCLK;
   inout         I2C_SDAT;	
	
	//////////////////////
   wire   scl_pad_i;
   wire   scl_pad_o;
   wire   scl_padoen_o;

   assign scl_pad_i = I2C_SCLK;
   assign I2C_SCLK = scl_padoen_o ? 1'bZ : scl_pad_o;

   wire   sda_pad_i;
   wire   sda_pad_o;
   wire   sda_padoen_o;

   assign sda_pad_i = I2C_SDAT;
   assign I2C_SDAT = sda_padoen_o ? 1'bZ : sda_pad_o;
	
	// registers
	wire  [15:0] prer; // clock prescale register
	reg  [ 7:0] ctr;  // control register
	reg  [ 7:0] txr;  // transmit register
   wire [ 7:0] rxr;  // receive register
	reg  [ 7:0] cr;   // command register
  // done signal: command completed, clear command register
	wire done/*synthesis keep*/;
  // core enable signal
	wire core_en;
  // status register signals
	wire irxack;
	wire i2c_busy;    // bus busy (start signal detected)
	wire i2c_al/*synthesis keep*/;      // i2c bus arbitration lost
	reg [7:0] read_data [0:31]/*synthesis noprune*/;
	
	assign prer=16'h18;
   assign core_en = 1'b1;	

  // decode command register
	wire sta  = cr[7]/*synthesis keep*/;
	wire sto  = cr[6]/*synthesis keep*/;
	wire rd   = cr[5]/*synthesis keep*/;
	wire wr   = cr[4]/*synthesis keep*/;
   wire iack = cr[3]/*synthesis keep*/;
	wire ack  = cr[0]/*synthesis keep*/;
	

 

	// hookup byte controller block
	i2c_master_byte_ctrl byte_controller (
		.clk      ( iCLK    ),
		.rst      ( 1'b0         ),
		.nReset   ( iRSTN        ),
		.ena      ( core_en      ),
		.clk_cnt  ( prer         ),
		.start    ( sta          ),
		.stop     ( sto          ),
		.read     ( rd           ),
		.write    ( wr           ),
		.ack_in   ( ack          ),
		.din      ( txr          ),
		.cmd_ack  ( done         ),
		.ack_out  ( irxack       ),
		.dout     ( rxr          ),
		.i2c_busy ( i2c_busy     ),
		.i2c_al   ( i2c_al       ),
		.scl_i    ( scl_pad_i    ),
		.scl_o    ( scl_pad_o    ),
		.scl_oen  ( scl_padoen_o ),
		.sda_i    ( sda_pad_i    ),
		.sda_o    ( sda_pad_o    ),
		.sda_oen  ( sda_padoen_o )
	);
	
reg pre_touch_int_n;
wire int_n/*synthesis keep*/;

always @(posedge iCLK or negedge iRSTN)
	  if (~iRSTN)
	    pre_touch_int_n <=  1'b0;
	  else 
	    pre_touch_int_n <= INT_n;

		 
assign 	int_n=({pre_touch_int_n,INT_n}==2'b10)?1'b1:1'b0;



	reg [3:0] c_state/*synthesis noprune*/; 
	reg [9:0] cnt;
	reg [5:0] read_cnt; 
	reg       flag;
   reg [7:0] data_reg/*synthesis noprune*/;

	always @(posedge iCLK or negedge iRSTN)
	  if (~iRSTN)
	    begin
	        c_state  <=  4'b0;
			  cnt<=0;
			  read_cnt<=0;
			  flag<=0;
			  oREADY<=0;
		 end
     else
	    begin
           case (c_state) // synopsys full_case parallel_case
			  
	          0:begin
			        if(int_n)
			           begin
			             cnt<=0;  
			             read_cnt<=0;
				          flag<=1;
				          oREADY<=0;
				        end
				
			         if(flag==1)
			            begin
	                    if (cnt[6]==1)
	                       begin
					              cnt<=0;
					              flag<=0;
					              c_state<=1;
					           end
				           else
					           cnt<=cnt+1; 
		               end 
			      end
					
	          1: begin  //write device_address
				      txr<=8'h70;
						if(done | i2c_al)
					      begin
					        cr[7:1]<=7'h0;
					        c_state<=2;
					      end
					   else
					      cr<=8'h90;
			       end		  
					 
		        2:begin  //wait
				      if (cnt[6]==1)
	                  begin
					         cnt<=0;
					         c_state<=3;
					      end
					   else
					      cnt<=cnt+1;
			       end
					 
				  3:begin   //write sub_address
			         txr<=8'h00;
		            if(done | i2c_al)
					      begin
					        cr[7:1]<=7'h0;
					        c_state<=4;
					      end
					   else
					        cr<=8'h10;
			       end
				  
		        4: begin  //wait
				       if (cnt[6]==1)
	                   begin
					         cnt<=0;
					         c_state<=5;
					       end
					    else
					       cnt<=cnt+1;
		           end	
					  
		        5:	begin   //write address with read bit
				  		  txr<=8'h71;  
                    if(done | i2c_al)
					        begin
					          cr[7:1]<=7'h0;
					          c_state<= 6;
					        end
					     else
					        cr<=8'h90;
			         end			  
		
		        6:begin   //wait
				      if (cnt[5]==1)
	                  begin
					        cnt<=0;
					        if(read_cnt==6'd31)
						        begin
						          c_state<= 8 ;
							       read_cnt<= 0; 
							     end
					        else
					           c_state<=7;
					      end
					   else
					      cnt<=cnt+1;		  
			       end		
		         
				  7: begin   //read data
			           if(done | i2c_al)
					        begin
					           cr[7:1]<=7'h0;
						        read_data[read_cnt] <=rxr; //read
					           c_state<= 6 ;
							     read_cnt<=read_cnt+1; 
					        end
				        else 
					        begin
					           if(read_cnt==6'd30)
					              cr<=8'h21;
					           else
                             cr<=8'h20;
					        end
	              end
					  
	          8:begin   //stop  
          		   if(done | i2c_al)
					      begin
					         cr[7:1]<=7'h0;
					         c_state<= 9;
						      oREADY<=1;
					      end
					   else
					      cr<=8'h40; 
			      end	
					
				 9:begin
				    if (cnt[6]==1)
	                   begin
					         cnt<=0;
					         c_state<=0;
					         oREADY<=0;
					       end
					  else
					    cnt<=cnt+1;
		         end
			 
		       default:
	               c_state <= 0;

	     endcase
	 end	


wire [7:0] REG_GESTURE/*synthesis keep*/;
assign  REG_GESTURE=read_data[1];

wire [3:0] REG_TOUCH_COUNT;
assign   REG_TOUCH_COUNT=read_data[2][3:0];

always @(posedge iCLK or negedge iRSTN)
begin
	  if (~iRSTN)
	     begin
          oREG_GESTURE <= 0;
		    oREG_TOUCH_COUNT<=0;
		  end
	  else if(oREADY)
	        begin
			    oREG_TOUCH_COUNT<=REG_TOUCH_COUNT;
		       if(REG_GESTURE == 8'h10)
		          oREG_GESTURE <= 8'h14;
		       else if(REG_GESTURE == 8'h1c)
		          oREG_GESTURE <= 8'h10;
		       else if(REG_GESTURE == 8'h18)
		          oREG_GESTURE <= 8'h1c;
		       else if(REG_GESTURE == 8'h14)
		          oREG_GESTURE <= 8'h18;
		       else oREG_GESTURE <= REG_GESTURE;
		     end
end

	
wire [15:0] X1,Y1,X2,Y2,X3,Y3,X4,Y4,X5,Y5;	
assign  X1={4'b0,read_data[3][3:0],read_data[4]};
assign  Y1={4'b0,read_data[5][3:0],read_data[6]};

assign  X2={4'b0,read_data[9][3:0],read_data[10]};
assign  Y2={4'b0,read_data[11][3:0],read_data[12]};

assign  X3={4'b0,read_data[15][3:0],read_data[16]};
assign  Y3={4'b0,read_data[17][3:0],read_data[18]};

assign  X4={4'b0,read_data[21][3:0],read_data[22]};
assign  Y4={4'b0,read_data[23][3:0],read_data[24]};

assign  X5={4'b0,read_data[27][3:0],read_data[28]};
assign  Y5={4'b0,read_data[29][3:0],read_data[30]};	
	
always @(posedge iCLK or negedge iRSTN)
begin
	  if (~iRSTN)
	        begin
             oREG_X1<=0;
		       oREG_Y1<=0;
		       oREG_X2<=0;
		       oREG_Y2<=0;
		       oREG_X3<=0;
		       oREG_Y3<=0;
		       oREG_X4<=0;
		       oREG_Y4<=0;
		       oREG_X5<=0;
		       oREG_Y5<=0;
		     end 
	  else if(oREADY)
	        begin
             oREG_X1<=(X1*25)>>5;
             oREG_Y1<=(Y1<<2)/5;
             oREG_X2<=(X2*25)>>5;
             oREG_Y2<=(Y2<<2)/5;
             oREG_X3<=(X3*25)>>5;
             oREG_Y3<=(Y3<<2)/5;
             oREG_X4<=(X4*25)>>5;
             oREG_Y4<=(Y4<<2)/5;
             oREG_X5<=(X5*25)>>5;
             oREG_Y5<=(Y5<<2)/5;
		     end
end	
	

endmodule	


module i2c_master_byte_ctrl (
	clk, rst, nReset, ena, clk_cnt, start, stop, read, write, ack_in, din,
	cmd_ack, ack_out, dout, i2c_busy, i2c_al, scl_i, scl_o, scl_oen, sda_i, sda_o, sda_oen );

	//
	// inputs & outputs
	//
	input clk;     // master clock
	input rst;     // synchronous active high reset
	input nReset;  // asynchronous active low reset
	input ena;     // core enable signal

	input [15:0] clk_cnt; // 4x SCL

	// control inputs
	input       start;
	input       stop;
	input       read;
	input       write;
	input       ack_in;
	input [7:0] din;

	// status outputs
	output       cmd_ack;
	reg cmd_ack;
	output       ack_out;
	reg ack_out;
	output       i2c_busy;
	output       i2c_al;
	output [7:0] dout;

	// I2C signals
	input  scl_i;
	output scl_o;
	output scl_oen;
	input  sda_i;
	output sda_o;
	output sda_oen;


	//
	// Variable declarations
	//
`define I2C_CMD_NOP   4'b0000
`define I2C_CMD_START 4'b0001
`define I2C_CMD_STOP  4'b0010
`define I2C_CMD_WRITE 4'b0100
`define I2C_CMD_READ  4'b1000
	// statemachine
	parameter [4:0] ST_IDLE  = 5'b0_0000;
	parameter [4:0] ST_START = 5'b0_0001;
	parameter [4:0] ST_READ  = 5'b0_0010;
	parameter [4:0] ST_WRITE = 5'b0_0100;
	parameter [4:0] ST_ACK   = 5'b0_1000;
	parameter [4:0] ST_STOP  = 5'b1_0000;

	// signals for bit_controller
	reg  [3:0] core_cmd;
	reg        core_txd;
	wire       core_ack, core_rxd;

	// signals for shift register
	reg [7:0] sr; //8bit shift register
	reg       shift, ld;

	// signals for state machine
	wire       go;
	reg  [2:0] dcnt;
	wire       cnt_done;

	//
	// Module body
	//

	// hookup bit_controller
	i2c_master_bit_ctrl bit_controller (
		.clk     ( clk      ),
		.rst     ( rst      ),
		.nReset  ( nReset   ),
		.ena     ( ena      ),
		.clk_cnt ( clk_cnt  ),
		.cmd     ( core_cmd ),
		.cmd_ack ( core_ack ),
		.busy    ( i2c_busy ),
		.al      ( i2c_al   ),
		.din     ( core_txd ),
		.dout    ( core_rxd ),
		.scl_i   ( scl_i    ),
		.scl_o   ( scl_o    ),
		.scl_oen ( scl_oen  ),
		.sda_i   ( sda_i    ),
		.sda_o   ( sda_o    ),
		.sda_oen ( sda_oen  )
	);

	// generate go-signal
	assign go = (read | write | stop) & ~cmd_ack;

	// assign dout output to shift-register
	assign dout = sr;

	// generate shift register
	always @(posedge clk or negedge nReset)
	  if (!nReset)
	    sr <= #1 8'h0;
	  else if (rst)
	    sr <= #1 8'h0;
	  else if (ld)
	    sr <= #1 din;
	  else if (shift)
	    sr <= #1 {sr[6:0], core_rxd};

	// generate counter
	always @(posedge clk or negedge nReset)
	  if (!nReset)
	    dcnt <= #1 3'h0;
	  else if (rst)
	    dcnt <= #1 3'h0;
	  else if (ld)
	    dcnt <= #1 3'h7;
	  else if (shift)
	    dcnt <= #1 dcnt - 3'h1;

	assign cnt_done = ~(|dcnt);

	//
	// state machine
	//
	reg [4:0] c_state; // synopsis enum_state

	always @(posedge clk or negedge nReset)
	  if (!nReset)
	    begin
	        core_cmd <= #1 `I2C_CMD_NOP;
	        core_txd <= #1 1'b0;
	        shift    <= #1 1'b0;
	        ld       <= #1 1'b0;
	        cmd_ack  <= #1 1'b0;
	        c_state  <= #1 ST_IDLE;
	        ack_out  <= #1 1'b0;
	    end
	  else if (rst | i2c_al)
	   begin
	       core_cmd <= #1 `I2C_CMD_NOP;
	       core_txd <= #1 1'b0;
	       shift    <= #1 1'b0;
	       ld       <= #1 1'b0;
	       cmd_ack  <= #1 1'b0;
	       c_state  <= #1 ST_IDLE;
	       ack_out  <= #1 1'b0;
	   end
	else
	  begin
	      // initially reset all signals
	      core_txd <= #1 sr[7];
	      shift    <= #1 1'b0;
	      ld       <= #1 1'b0;
	      cmd_ack  <= #1 1'b0;

	      case (c_state) // synopsys full_case parallel_case
	        ST_IDLE:
	          if (go)
	            begin
	                if (start)
	                  begin
	                      c_state  <= #1 ST_START;
	                      core_cmd <= #1 `I2C_CMD_START;
	                  end
	                else if (read)
	                  begin
	                      c_state  <= #1 ST_READ;
	                      core_cmd <= #1 `I2C_CMD_READ;
	                  end
	                else if (write)
	                  begin
	                      c_state  <= #1 ST_WRITE;
	                      core_cmd <= #1 `I2C_CMD_WRITE;
	                  end
	                else // stop
	                  begin
	                      c_state  <= #1 ST_STOP;
	                      core_cmd <= #1 `I2C_CMD_STOP;
	                  end

	                ld <= #1 1'b1;
	            end

	        ST_START:
	          if (core_ack)
	            begin
	                if (read)
	                  begin
	                      c_state  <= #1 ST_READ;
	                      core_cmd <= #1 `I2C_CMD_READ;
	                  end
	                else
	                  begin
	                      c_state  <= #1 ST_WRITE;
	                      core_cmd <= #1 `I2C_CMD_WRITE;
	                  end

	                ld <= #1 1'b1;
	            end

	        ST_WRITE:
	          if (core_ack)
	            if (cnt_done)
	              begin
	                  c_state  <= #1 ST_ACK;
	                  core_cmd <= #1 `I2C_CMD_READ;
	              end
	            else
	              begin
	                  c_state  <= #1 ST_WRITE;       // stay in same state
	                  core_cmd <= #1 `I2C_CMD_WRITE; // write next bit
	                  shift    <= #1 1'b1;
	              end

	        ST_READ:
	          if (core_ack)
	            begin
	                if (cnt_done)
	                  begin
	                      c_state  <= #1 ST_ACK;
	                      core_cmd <= #1 `I2C_CMD_WRITE;
	                  end
	                else
	                  begin
	                      c_state  <= #1 ST_READ;       // stay in same state
	                      core_cmd <= #1 `I2C_CMD_READ; // read next bit
	                  end

	                shift    <= #1 1'b1;
	                core_txd <= #1 ack_in;
	            end

	        ST_ACK:
	          if (core_ack)
	            begin
	               if (stop)
	                 begin
	                     c_state  <= #1 ST_STOP;
	                     core_cmd <= #1 `I2C_CMD_STOP;
	                 end
	               else
	                 begin
	                     c_state  <= #1 ST_IDLE;
	                     core_cmd <= #1 `I2C_CMD_NOP;

	                     // generate command acknowledge signal
	                     cmd_ack  <= #1 1'b1;
	                 end

	                 // assign ack_out output to bit_controller_rxd (contains last received bit)
	                 ack_out <= #1 core_rxd;

	                 core_txd <= #1 1'b1;
	             end
	           else
	             core_txd <= #1 ack_in;

	        ST_STOP:
	          if (core_ack)
	            begin
	                c_state  <= #1 ST_IDLE;
	                core_cmd <= #1 `I2C_CMD_NOP;

	                // generate command acknowledge signal
	                cmd_ack  <= #1 1'b1;
	            end

	      endcase
	  end
endmodule






module i2c_master_bit_ctrl(
	clk, rst, nReset, 
	clk_cnt, ena, cmd, cmd_ack, busy, al, din, dout,
	scl_i, scl_o, scl_oen, sda_i, sda_o, sda_oen
	);

`define I2C_CMD_NOP   4'b0000
`define I2C_CMD_START 4'b0001
`define I2C_CMD_STOP  4'b0010
`define I2C_CMD_WRITE 4'b0100
`define I2C_CMD_READ  4'b1000
	
	//
	// inputs & outputs
	//
	input clk;
	input rst;
	input nReset;
	input ena;            // core enable signal

	input [15:0] clk_cnt; // clock prescale value

	input  [3:0] cmd;
	output       cmd_ack; // command complete acknowledge
	reg cmd_ack;
	output       busy;    // i2c bus busy
	reg busy;
	output       al;      // i2c bus arbitration lost
	reg al;

	input  din;
	output dout;
	reg dout;

	// I2C lines
	input  scl_i;         // i2c clock line input
	output scl_o;         // i2c clock line output
	output scl_oen;       // i2c clock line output enable (active low)
	reg scl_oen;
	input  sda_i;         // i2c data line input
	output sda_o;         // i2c data line output
	output sda_oen;       // i2c data line output enable (active low)
	reg sda_oen;


	//
	// variable declarations
	//

	
	
	reg sSCL, sSDA;             // synchronized SCL and SDA inputs
	reg dscl_oen;               // delayed scl_oen
	reg sda_chk;                // check SDA output (Multi-master arbitration)
	reg clk_en;                 // clock generation signals
	wire slave_wait;
//	reg [15:0] cnt = clk_cnt;   // clock divider counter (simulation)
	reg [15:0] cnt;             // clock divider counter (synthesis)

	// state machine variable
	reg [16:0] c_state;

	//
	// module body
	//

	// whenever the slave is not ready it can delay the cycle by pulling SCL low
	// delay scl_oen
	always @(posedge clk)
	  dscl_oen <= #1 scl_oen;

	assign slave_wait = dscl_oen && !sSCL;


	// generate clk enable signal
	always @(posedge clk or negedge nReset)
	  if(~nReset)
	    begin
	        cnt    <= #1 16'h0;
	        clk_en <= #1 1'b1;
	    end
	  else if (rst)
	    begin
	        cnt    <= #1 16'h0;
	        clk_en <= #1 1'b1;
	    end
	  else if ( ~|cnt || ~ena)
	    if (~slave_wait)
	      begin
	          cnt    <= #1 clk_cnt;
	          clk_en <= #1 1'b1;
	      end
	    else
	      begin
	          cnt    <= #1 cnt;
	          clk_en <= #1 1'b0;
	      end
	  else
	    begin
                cnt    <= #1 cnt - 16'h1;
	        clk_en <= #1 1'b0;
	    end


	// generate bus status controller
	reg dSCL, dSDA;
	reg sta_condition;
	reg sto_condition;

	// synchronize SCL and SDA inputs
	// reduce metastability risc
	always @(posedge clk or negedge nReset)
	  if (~nReset)
	    begin
	        sSCL <= #1 1'b1;
	        sSDA <= #1 1'b1;

	        dSCL <= #1 1'b1;
	        dSDA <= #1 1'b1;
	    end
	  else if (rst)
	    begin
	        sSCL <= #1 1'b1;
	        sSDA <= #1 1'b1;

	        dSCL <= #1 1'b1;
	        dSDA <= #1 1'b1;
	    end
	  else
	    begin
	        sSCL <= #1 scl_i;
	        sSDA <= #1 sda_i;

	        dSCL <= #1 sSCL;
	        dSDA <= #1 sSDA;
	    end

	// detect start condition => detect falling edge on SDA while SCL is high
	// detect stop condition => detect rising edge on SDA while SCL is high
	always @(posedge clk or negedge nReset)
	  if (~nReset)
	    begin
	        sta_condition <= #1 1'b0;
	        sto_condition <= #1 1'b0;
	    end
	  else if (rst)
	    begin
	        sta_condition <= #1 1'b0;
	        sto_condition <= #1 1'b0;
	    end
	  else
	    begin
	        sta_condition <= #1 ~sSDA &  dSDA & sSCL;
	        sto_condition <= #1  sSDA & ~dSDA & sSCL;
	    end

	// generate i2c bus busy signal
	always @(posedge clk or negedge nReset)
	  if(!nReset)
	    busy <= #1 1'b0;
	  else if (rst)
	    busy <= #1 1'b0;
	  else
	    busy <= #1 (sta_condition | busy) & ~sto_condition;

	// generate arbitration lost signal
	// aribitration lost when:
	// 1) master drives SDA high, but the i2c bus is low
	// 2) stop detected while not requested
	reg cmd_stop;
	always @(posedge clk or negedge nReset)
	  if (~nReset)
	    cmd_stop <= #1 1'b0;
	  else if (rst)
	    cmd_stop <= #1 1'b0;
	  else if (clk_en)
	    cmd_stop <= #1 cmd == `I2C_CMD_STOP;

	always @(posedge clk or negedge nReset)
	  if (~nReset)
	    al <= #1 1'b0;
	  else if (rst)
	    al <= #1 1'b0;
	  else
	    al <= #1 (sda_chk & ~sSDA & sda_oen) | (|c_state & sto_condition & ~cmd_stop);


	// generate dout signal (store SDA on rising edge of SCL)
	always @(posedge clk)
	  if(sSCL & ~dSCL)
	    dout <= #1 sSDA;

	// generate statemachine

	// nxt_state decoder
	parameter [16:0] idle    = 17'b0_0000_0000_0000_0000;
	parameter [16:0] start_a = 17'b0_0000_0000_0000_0001;
	parameter [16:0] start_b = 17'b0_0000_0000_0000_0010;
	parameter [16:0] start_c = 17'b0_0000_0000_0000_0100;
	parameter [16:0] start_d = 17'b0_0000_0000_0000_1000;
	parameter [16:0] start_e = 17'b0_0000_0000_0001_0000;
	parameter [16:0] stop_a  = 17'b0_0000_0000_0010_0000;
	parameter [16:0] stop_b  = 17'b0_0000_0000_0100_0000;
	parameter [16:0] stop_c  = 17'b0_0000_0000_1000_0000;
	parameter [16:0] stop_d  = 17'b0_0000_0001_0000_0000;
	parameter [16:0] rd_a    = 17'b0_0000_0010_0000_0000;
	parameter [16:0] rd_b    = 17'b0_0000_0100_0000_0000;
	parameter [16:0] rd_c    = 17'b0_0000_1000_0000_0000;
	parameter [16:0] rd_d    = 17'b0_0001_0000_0000_0000;
	parameter [16:0] wr_a    = 17'b0_0010_0000_0000_0000;
	parameter [16:0] wr_b    = 17'b0_0100_0000_0000_0000;
	parameter [16:0] wr_c    = 17'b0_1000_0000_0000_0000;
	parameter [16:0] wr_d    = 17'b1_0000_0000_0000_0000;

	always @(posedge clk or negedge nReset)
	  if (!nReset)
	    begin
	        c_state <= #1 idle;
	        cmd_ack <= #1 1'b0;
	        scl_oen <= #1 1'b1;
	        sda_oen <= #1 1'b1;
	        sda_chk <= #1 1'b0;
	    end
	  else if (rst | al)
	    begin
	        c_state <= #1 idle;
	        cmd_ack <= #1 1'b0;
	        scl_oen <= #1 1'b1;
	        sda_oen <= #1 1'b1;
	        sda_chk <= #1 1'b0;
	    end
	  else
	    begin
	        cmd_ack   <= #1 1'b0; // default no command acknowledge + assert cmd_ack only 1clk cycle

	        if (clk_en)
	          case (c_state)
	            // idle state
	            idle:
	            begin
	                case (cmd)
	                  `I2C_CMD_START:
	                     c_state <= #1 start_a;

	                  `I2C_CMD_STOP:
	                     c_state <= #1 stop_a;

	                  `I2C_CMD_WRITE:
	                     c_state <= #1 wr_a;

	                  `I2C_CMD_READ:
	                     c_state <= #1 rd_a;

	                  default:
	                    c_state <= #1 idle;
	                endcase

	                scl_oen <= #1 scl_oen; // keep SCL in same state
	                sda_oen <= #1 sda_oen; // keep SDA in same state
	                sda_chk <= #1 1'b0;    // don't check SDA output
	            end

	            // start
	            start_a:
	            begin
	                c_state <= #1 start_b;
	                scl_oen <= #1 scl_oen; // keep SCL in same state
	                sda_oen <= #1 1'b1;    // set SDA high
	                sda_chk <= #1 1'b0;    // don't check SDA output
	            end

	            start_b:
	            begin
	                c_state <= #1 start_c;
	                scl_oen <= #1 1'b1; // set SCL high
	                sda_oen <= #1 1'b1; // keep SDA high
	                sda_chk <= #1 1'b0; // don't check SDA output
	            end

	            start_c:
	            begin
	                c_state <= #1 start_d;
	                scl_oen <= #1 1'b1; // keep SCL high
	                sda_oen <= #1 1'b0; // set SDA low
	                sda_chk <= #1 1'b0; // don't check SDA output
	            end

	            start_d:
	            begin
	                c_state <= #1 start_e;
	                scl_oen <= #1 1'b1; // keep SCL high
	                sda_oen <= #1 1'b0; // keep SDA low
	                sda_chk <= #1 1'b0; // don't check SDA output
	            end

	            start_e:
	            begin
	                c_state <= #1 idle;
	                cmd_ack <= #1 1'b1;
	                scl_oen <= #1 1'b0; // set SCL low
	                sda_oen <= #1 1'b0; // keep SDA low
	                sda_chk <= #1 1'b0; // don't check SDA output
	            end

	            // stop
	            stop_a:
	            begin
	                c_state <= #1 stop_b;
	                scl_oen <= #1 1'b0; // keep SCL low
	                sda_oen <= #1 1'b0; // set SDA low
	                sda_chk <= #1 1'b0; // don't check SDA output
	            end

	            stop_b:
	            begin
	                c_state <= #1 stop_c;
	                scl_oen <= #1 1'b1; // set SCL high
	                sda_oen <= #1 1'b0; // keep SDA low
	                sda_chk <= #1 1'b0; // don't check SDA output
	            end

	            stop_c:
	            begin
	                c_state <= #1 stop_d;
	                scl_oen <= #1 1'b1; // keep SCL high
	                sda_oen <= #1 1'b0; // keep SDA low
	                sda_chk <= #1 1'b0; // don't check SDA output
	            end

	            stop_d:
	            begin
	                c_state <= #1 idle;
	                cmd_ack <= #1 1'b1;
	                scl_oen <= #1 1'b1; // keep SCL high
	                sda_oen <= #1 1'b1; // set SDA high
	                sda_chk <= #1 1'b0; // don't check SDA output
	            end

	            // read
	            rd_a:
	            begin
	                c_state <= #1 rd_b;
	                scl_oen <= #1 1'b0; // keep SCL low
	                sda_oen <= #1 1'b1; // tri-state SDA
	                sda_chk <= #1 1'b0; // don't check SDA output
	            end

	            rd_b:
	            begin
	                c_state <= #1 rd_c;
	                scl_oen <= #1 1'b1; // set SCL high
	                sda_oen <= #1 1'b1; // keep SDA tri-stated
	                sda_chk <= #1 1'b0; // don't check SDA output
	            end

	            rd_c:
	            begin
	                c_state <= #1 rd_d;
	                scl_oen <= #1 1'b1; // keep SCL high
	                sda_oen <= #1 1'b1; // keep SDA tri-stated
	                sda_chk <= #1 1'b0; // don't check SDA output
	            end

	            rd_d:
	            begin
	                c_state <= #1 idle;
	                cmd_ack <= #1 1'b1;
	                scl_oen <= #1 1'b0; // set SCL low
	                sda_oen <= #1 1'b1; // keep SDA tri-stated
	                sda_chk <= #1 1'b0; // don't check SDA output
	            end

	            // write
	            wr_a:
	            begin
	                c_state <= #1 wr_b;
	                scl_oen <= #1 1'b0; // keep SCL low
	                sda_oen <= #1 din;  // set SDA
	                sda_chk <= #1 1'b0; // don't check SDA output (SCL low)
	            end

	            wr_b:
	            begin
	                c_state <= #1 wr_c;
	                scl_oen <= #1 1'b1; // set SCL high
	                sda_oen <= #1 din;  // keep SDA
	                sda_chk <= #1 1'b1; // check SDA output
	            end

	            wr_c:
	            begin
	                c_state <= #1 wr_d;
	                scl_oen <= #1 1'b1; // keep SCL high
	                sda_oen <= #1 din;
	                sda_chk <= #1 1'b1; // check SDA output
	            end

	            wr_d:
	            begin
	                c_state <= #1 idle;
	                cmd_ack <= #1 1'b1;
	                scl_oen <= #1 1'b0; // set SCL low
	                sda_oen <= #1 din;
	                sda_chk <= #1 1'b0; // don't check SDA output (SCL low)
	            end

	            default:
	                c_state <= #1 idle;

	          endcase
	    end


	// assign scl and sda output (always gnd)
	assign scl_o = 1'b0;
	assign sda_o = 1'b0;

endmodule
	            
	