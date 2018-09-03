library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Racquetball is
   port( CLOCK_50 : in std_logic;
         SW : in std_logic_vector(9 downto 0);
         KEY : in std_logic_vector(3 downto 0);
         HEX0, HEX1, HEX2, HEX3, HEX4, HEX5: out std_logic_vector(6 DOWNTO 0);
			LEDR: out std_logic_vector(9 downto 0);
         GPIO_1: out std_logic_vector(31 downto 0);
         MTL_TOUCH_INT_n : in std_logic;
         MTL_TOUCH_I2C_SCL : out std_logic;
         MTL_TOUCH_I2C_SDA : inout std_logic
         );
end entity;

architecture DE1_SoC_MTL2 of Racquetball is
   alias clock : std_logic is Clock_50;
   alias reset : std_logic is KEY(0);
   
   constant background : std_logic_vector(2 downto 0) := "000";
   constant pcolor : std_logic_vector(2 downto 0) := "001"; --Player1
   constant p2color : std_logic_vector(2 downto 0) := "010"; --Player2
   constant border : std_logic_vector(2 downto 0) := "011"; 
   constant lives_sprite : std_logic_vector(2 downto 0) := "100";
   constant game_over_sprite: std_logic_vector(2 downto 0) := "101";
	
   constant speed_on : std_logic_vector(2 downto 0) := "110";
   constant speed_off : std_logic_vector(2 downto 0) := "111";
   
   constant screen_width:  integer := 50;
   constant screen_height: integer := 30;
   
	signal lives, lives2: unsigned( 3 downto 0) := "0011";
	signal newgame : boolean;
	
   signal mem_in, mem_out, vdata: std_logic_vector(2 downto 0);
   signal mem_adr: std_logic_vector(10 downto 0);
   signal mem_wr: std_logic;
   signal slow_clock: std_logic;
   signal x, player2x, old_x : unsigned (5 downto 0);
   signal y, player2y, old_y : unsigned (4 downto 0);
   signal go : Boolean;
  
   signal px : unsigned (5 downto 0);
   signal py : unsigned(4 downto 0);
	
   signal LeftPixel1, TopPixel1, BottomPixel1, RightPixel1: unsigned(2 downto 0);
  -- signal LeftPixel2, TopPixel2, BottomPixel2, RightPixel2: unsigned(2 downto 0);
   
	signal op_num : integer range 0 to 3;
   type display is array (0 to 3) of std_logic_vector(15 downto 0);
   constant OP: display :=
            (x"5102", -- "StOP"
             x"304C", -- "gO=L"
             x"3046",  -- "gO=r"
				 x"304A"
             );

   type state is (clean0, clean1, clean2, clean3, sync1, sync2,
               perase1, perase2, pupdate,pupdate2,pdraw1, pdraw10, pdraw2, pdraw20, update1, 
               update2, update3, update4, update5, update6, update7, 
               update8, update9, update10, update11, erase1, erase2,
               bupdate, draw1, draw2,restart,ws0,ws1,ws2,ws3, move0, move1,
					collision_p1,collision_p2, end_p1, end_p2, end2_p1, end2_p2,
					update100,update200,update300,update400,update500,update600,
					update700,update800,update900);
   

   signal SV : state;
      
   type direction is (nothing,p2down,p2left,p2right,p2up);
   signal dir: direction;

   type pdirection  is (nothing,pleft, pright, pdown, pup);
   signal pdir: pdirection;

   signal VGA_R, VGA_G, VGA_B : std_logic_vector(7 downto 0);
   alias  VGA_HS : std_logic is GPIO_1(30); --HSD
   alias  VGA_VS : std_logic is GPIO_1(31); --VSD
   alias  DCLK : std_logic is GPIO_1(1);  --pixel clock = 33.3MHz

   TYPE Touch_state IS (wait_for_ready, get_code, examine);
   SIGNAL TS : Touch_state;   
	
	TYPE Touch_gesture IS(wait_for_ready2, examine2);
	SIGNAL TG : Touch_gesture;
	
   signal gesture : std_logic_vector(7 downto 0);
   signal ready: std_logic;
   
   signal speed, old_speed: unsigned(3 downto 0);
   signal queue: std_logic_vector(1 downto 0);
   
   signal AI : std_logic_vector(3 downto 0);
	
	Signal X1 : std_logic_vector(9 downto 0);
   Signal Y1 : std_logic_vector(8 downto 0);
   Signal TX : unsigned(9 downto 0);
   Signal TY : unsigned(8 downto 0);
      
   
   component i2c_touch_config is port(
      iCLK : in std_logic;
      iRSTN : in std_logic;
      oREADY : out std_logic;
      INT_n : in std_logic;
      
      oREG_X1 : out std_logic_vector(9 downto 0);
      oREG_Y1 : out std_logic_vector(8 downto 0);
      oREG_X2 : out std_logic_vector(9 downto 0);
      oREG_Y2 : out std_logic_vector(8 downto 0);
      oREG_X3 : out std_logic_vector(9 downto 0);
      oREG_Y3 : out std_logic_vector(8 downto 0);
      oREG_X4 : out std_logic_vector(9 downto 0);        
      oREG_Y4 : out std_logic_vector(8 downto 0);
      oREG_X5 : out std_logic_vector(9 downto 0);
      oREG_Y5 : out std_logic_vector(8 downto 0);
      oREG_GESTURE : out std_logic_vector(7 downto 0);
      oREG_TOUCH_COUNT : out std_logic_vector(3 downto 0);
      I2C_SDAT : inout std_logic;
      I2C_SCLK : out std_logic
   ); end component i2c_touch_config;
   

begin
   GPIO_1(10 downto 3) <= VGA_R;
   GPIO_1(21) <= VGA_G(7);
   GPIO_1(19 downto 18) <= VGA_G(6 downto 5);
   GPIO_1(15 downto 11) <= VGA_G(4 downto 0);
   GPIO_1(28 downto 22) <= VGA_B(7 downto 1);
   GPIO_1(20) <= VGA_B(0);
   
  vga_interface : entity work.vga_sprite port map(
      clock => clock,   
      reset => not reset,  
      mem_adr => mem_adr,
      mem_out => mem_out,
      mem_in => mem_in,
      mem_wr => mem_wr,   
      vga_hs => vga_hs,
      vga_vs => vga_vs,
		pclock => DCLK,
      r => vga_r,
      g => vga_g,
      b => vga_b
   );
   mem_adr <= std_logic_vector(y) & std_logic_vector(x);

   Terasic_Touch_IP: i2c_touch_config port map(
      iclk => clock_50,
      iRSTN => key(0),
      int_n => MTL_TOUCH_INT_n,
      oready => ready,
      oREG_X1 => X1,
      oREG_Y1 => Y1,
      oreg_gesture => gesture,
      i2c_sclk => MTL_TOUCH_I2C_SCL,
      i2c_sdat => MTL_TOUCH_I2C_SDA
   );

   dsp0: entity work.sevenseg port map (OP(op_num)(3 downto 0), HEX0);
   dsp1: entity work.sevenseg port map (OP(op_num)(7 downto 4), HEX1);
   dsp2: entity work.sevenseg port map (OP(op_num)(11 downto 8), HEX2);
   dsp3: entity work.sevenseg port map (OP(op_num)(15 downto 12), HEX3);
	
--	LEDR(9) <= '0';
--	LEDR(8) <= '0';
--	LEDR(7) <= '0';
--	LEDR(6) <= '0';	
--	LEDR(5) <= '0';	
--	--LEDR(4) <= '0';
--	--LEDR(3) <= '0';	
--	LEDR(2) <= '0';	
--	LEDR(1) <= '0';
--	--LEDR(0) <= '0';
--   
--	HEX0 <= "1111111";
--   HEX1 <= "1111111";
--	HEX2 <= "1111111";
--   HEX3 <= "1111111";
--	HEX4 <= "1111111";
--   HEX5 <= "1111111";
   ------------------------------------------------------
   Touch_Sensor_Interface: process(CLOCK, reset)
   begin
      if(reset = '0') then 
         speed <= x"1";
			AI <= "0001";
         TS <= wait_for_ready;
      
		elsif(clock'event AND clock = '1') then
         CASE TS IS
            WHEN wait_for_ready =>
               if(ready='1') then
                  TS <= get_code;
               end if;
					
            WHEN get_code =>
               TX <= unsigned(X1);
               TY <= unsigned(Y1);
               TS <= examine;
              
            WHEN examine => --Done
               if(TX >= 8 and TX <= 15 and TY>=80 and TY<=87) then
						speed <= x"8";
					elsif(TX >= 8 and TX <= 15 and TY>=96 and TY<=103) then 
						speed <= x"4";
					elsif(TX >= 8 and TX <= 15 and TY>=112 and TY<=119) then
						speed <= x"2";
					elsif(TX >= 8 and TX <= 15 and TY>=128 and TY<=135) then
						speed <= x"1";
					elsif(TX >= 384 and TX <= 393 and TY>=80 and TY<=87) then
						AI <= "0001";
					elsif(TX >= 384 and TX <= 393 and TY>=96 and TY<=103) then 
						AI <= "0010";
					elsif(TX >= 384 and TX <= 393 and TY>=112 and TY<=119) then
						AI <= "0011";
					elsif(TX >= 384 and TX <= 393 and TY>=128 and TY<=135) then
						AI <= "0100";
               end if;
               TS <= wait_for_ready;
               
            WHEN OTHERS =>
               TS <= wait_for_ready;
         END CASE;
      end if;     
   end process;
	
	Touch_gesture_handler: process(CLOCK, reset)
   begin
		if(reset = '0') then	
			go <= false;		
			pdir <= nothing;	
			dir <= nothing;
			OP_num <= 0;		
			TG <= wait_for_ready2;
			--newgame <= true;
			
		elsif(clock'event AND clock = '1') then
			CASE TG IS
				WHEN wait_for_ready2 =>
					if(ready='1') then
						TG <= examine2;
					end if;
				WHEN examine2 =>	
					if (newgame = true) then
						go <= false;
						pdir <= nothing;
						dir <= nothing;
						--newgame <= false;
						
					elsif(gesture = x"10") then	--Move Up
						go <= true;
						OP_num <= 3;
						pdir <= pup;
				
					elsif(gesture = x"18") then	--Move Down
						go <= true;
						pdir <= pdown;
						OP_num <= 0;
						
					elsif(gesture = x"14") then	--Move Left
						go <= true;
						pdir <= pleft;
						OP_num <= 1;
						
					elsif(gesture = x"1C") then	--Move Right
						go <= true;
						pdir <= pright;
						OP_num <= 2;	
					
					end if;
				WHEN OTHERS =>
					TG <= wait_for_ready2;
			END CASE;
		end if;		
   end process;
	
   ------------------------------------------------------
   display_clock: process(clock, reset) --Done
      variable loopcount : integer range 0 to 200000;
      variable switchcount : integer range 0 to 15;
   begin
      if(reset = '0') then 
         loopcount := 0;
         switchcount := 0;
         slow_clock <= '0';
      elsif(clock'event AND clock = '1') then
         if(loopcount >= 199999) then
            loopcount := 0;
            if(switchcount >= speed) then
               slow_clock <= not slow_clock;
               switchcount := 0;
            else
               switchcount := switchcount + 1;
            end if;
         else
            loopcount := loopcount + 1;
         end if;
      end if;     
      end process;
      ----------------------------------------------------------
      main: process(clock, reset)
      variable count : integer range 0 to 7;
      begin
      
      if(reset = '0') then       
         mem_wr <= '0';    ------------------------------
         x <= "000000";   --initialization Video RAM
         y <= "00000"; --address: x=0 and y=0
              ------------------------------
     
			player2x <= to_unsigned(40, 6); 
			player2y <= to_unsigned(15,5);	  
         px <= to_unsigned(20, 6); 
			py <= to_unsigned(15,5);	
         lives <= "0011";
			lives2 <= "0011";
			LeftPixel1 <= "000";
			RightPixel1 <= "000"; 
			TopPixel1 <= "000";
			BottomPixel1 <= "000";
			newgame <= false;
			SV <= clean0;
      
		elsif(clock'event AND clock = '1') then
         case SV is
            when clean0 => 
               mem_wr <= '1';  
					px <= to_unsigned(20, 6);	
					py <= to_unsigned(15,5); 
					player2x <= to_unsigned(40, 6); 
					player2y <= to_unsigned(15,5);	
               if(y = py and x = py) then
                  mem_in <= pcolor; --Works
					elsif(x = Player2x and y = Player2y) then
						mem_in <= p2color;
               elsif(lives = "0011" and (y = 0 and (x = 7 or x = 9 or x = 11))) then
                  mem_in <= lives_sprite; --Works
               elsif(lives = "0010" and (y = 0 and (x = 9 or x = 11))) then
                  mem_in <= lives_sprite; --Works
               elsif(lives = "0001" and (y = 0 and x = 11)) then
                  mem_in <= lives_sprite; --Works
               elsif((x = 3 and (y >= 1 and y <= 29)) or (x = 46 and (y >= 1 and y <= 29)) or (y = 1 and (x >= 3 and x <= 46)) or (y = 29 and (x >= 3 and x <= 46))) then
                  mem_in <= border;    --border color
					else
                  mem_in <= background;   
               end if;
               SV <= clean1;
               
            when clean1 => --Done
               x <= x+1;
               SV <= clean2;
            
				when clean2 => --Done
               mem_wr <= '0';    -- disable the write enable
               if(x> screen_width - 1) then 
                  x<= "000000";
                  y <= y+1;
                  SV <= clean3;
               else
                  SV <= clean0;
               end if;
               
            when clean3 => --Done
               if(y > screen_height - 1) then
                  SV <= move0;
               else
                  SV <= clean0;
               end if;
               
          when move0 =>
             queue <= queue(0) & slow_clock;
             SV <= move1;
          when move1 =>
             if (speed /= old_speed) then
                old_speed <= speed;
                SV <= ws0;
             elsif(queue = "01") then
                SV <= pupdate;               --update speed button sprites    
             else
                SV <= move0;
             end if;
   
   --------------------------------------------------
            when ws0 =>
               count := 0;
               old_x <= x;
               old_y <= y;
               SV <= ws1;
            when ws1 => --Drawing/Updating speed buttons
               case count is
                  when 0 =>
                     X <= to_unsigned(1, 6);
                     Y <= to_unsigned(10, 5);
                     if(speed = x"8") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  when 1 =>
                     X <= to_unsigned(1, 6);
                     Y <= to_unsigned(12, 5);
                     if(speed = x"4") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  when 2 =>
                     X <= to_unsigned(1, 6);
                     Y <= to_unsigned(14, 5);
                     if(speed = x"2") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  when 3 =>
                     X <= to_unsigned(1, 6);
                     Y <= to_unsigned(16, 5);
                     if(speed = x"1") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
				
						when 4 => --AI button 1
                     X <= to_unsigned(48, 6);
                     Y <= to_unsigned(10, 5);
                     if(AI = "0011") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  
						when 5 => --AI button 2
                     X <= to_unsigned(48, 6);
                     Y <= to_unsigned(12, 5);
                     if(AI = "0010") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";						x <= x - 1;	
					   y <= y - 1;
                     end if;
                  
						when 6 => --AI button 3
                     X <= to_unsigned(48, 6);
                     Y <= to_unsigned(14, 5);
                     if(AI = "0001") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  
						when 7 => --AI button 4
                     X <= to_unsigned(48, 6);
                     Y <= to_unsigned(16, 5);
                     if(AI = "0000") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;	
                  when others =>						x <= x - 1;	
					   y <= y - 1;
                     null;
               end case;
               mem_wr <= '1'; 
               SV <= ws2;  
            
				when ws2 =>
               count := count + 1;
               SV <= ws3;
            when ws3 =>
               mem_wr <= '0'; 
               if(count <= 7) then 
                  SV <= ws1;
               else
                  X <= old_x;
                  Y <= old_y;
                  SV <= move0;
               end if;
            --------------------------------------------------
            
--            when sync1 =>        --Sync1 and sync2 wait
--               mem_wr <= '0';    --for the rising edge
--               if(slow_clock = '0') then  --of slow_clock
--                  SV <= sync2;
--               end ifC");
--            
--				when sync2 =>
--               if(slow_clock = '1') then
--                  SV <= pupdate;						x <= x - 1;	
					   y <= y - 1;
--               end if;           
----      
           when pupdate => --Done
				case pdir is 
					when nothing =>
						LEDR(8) <= '1';
					when pleft =>		
						if(go ) then				
							px <= px - 1;					
						end if;
					when pright =>
						if(go) then
							px <= px + 1;
						end if;
					when pup =>
						if(go) then
							py <= py - 1;
						end if;
					when pdown =>
						if (go) then 
							py <= py + 1;
						end if;
					when others =>
						null;
				end case;
              SV <= pupdate2;
           
			  when pupdate2 => --Done
				case dir is 
					when nothing =>
						LEDR(5) <= '1';
					when p2left =>		
						if(go ) then				
							player2x <= player2x - 1;					
						end if;
					when p2right =>
						if(go ) then
							player2x <= player2x + 1;
						end if;
					when p2up =>
						if(go ) then
							player2y <= player2y - 1;
						end if;
					when p2down =>
						if (go) then 
							player2y <= player2y + 1;
							end if;
				end case;
              SV <= pdraw10;
				  
			  when pdraw10 =>
						x <= px ;
						y <= py;
						mem_wr <= '1';		
						mem_in <= pcolor;
						SV <= pdraw20;
					
					when pdraw20 =>
						SV <= update100;					
					when update100 =>	
						mem_wr <= '0';
						x <= x - 1;	
						SV <= update200;
					when update200 =>
						SV <= update300;
					when update300 =>
						LeftPixel1 <= unsigned(mem_out);				
						y <= y + 1;	
						x <= x + 1;
						SV <= update400;
					when update400 =>		
						SV <= update500;
					when update500 =>	
						BottomPixel1 <= unsigned(mem_out);				
						x <= x + 1;
						y <= y - 1;
						SV <= update600;		
					when update600 =>		
						SV <= update700;
					when update700 =>
						RightPixel1 <= unsigned(mem_out);
						y <= y - 1;
						x <= x - 1;
						SV <= update800;	
					when update800 =>		
						SV <= update900;
					when update900 =>
						TopPixel1 <= unsigned(mem_out);
						SV <= collision_p1;
					        	
          
				when collision_p1 =>
					if( pdir = pleft and (LeftPixel1 /= "000")) then 
						SV	<= end_p1;
					elsif(pdir = pright and (RightPixel1 /= "000")) then
						SV <= end_p1;
					elsif(pdir = pdown and (BottomPixel1 /= "000")) then
						SV <= end_p1;
					elsif(pdir = pup and (TopPixel1 /= "000")) then  
						SV <= end_p1;
					else 
				   	SV<= pdraw1;
					end if;
					
				when pdraw1 =>
				if(go) then
					x <= player2x;
					y <= player2y;
					mem_wr <= '1';		
					mem_in <= p2color;
					SV <= pdraw2;
				else
					SV <= draw1;
				end if;
				when pdraw2 =>
						SV <= update1;					
				when update1 =>	
						mem_wr <= '0';	
						x <= x - 1;
					
						SV <= update2;
				when update2 =>
						SV <= update3;
				when update3 =>
						LeftPixel1 <= unsigned(mem_out);	
						y <= y + 1;	
						x <= x + 1;	
						SV <= update4;
				when update4 =>	
						SV <= update5;
				when update5 =>
						BottomPixel1 <= unsigned(mem_out);		
						x <= x + 1;
						y <= y - 1;
						SV <= update6;		
				when update6 =>	
						SV <= update7;
				when update7 =>
						RightPixel1 <= unsigned(mem_out);
						y <= y - 1;
					   x <= x - 1;	
						SV <= update8;	
				when update8 =>	
						SV <= update9;
				when update9 =>
						TopPixel1 <= unsigned(mem_out);
						SV <= collision_p2;
						
				when collision_p2 =>
					if( dir = p2left and (LeftPixel1 /= "000")) then 
						--LEDR(8) <= '1';
						SV	<= end_p2;
					elsif(dir = p2right and (RightPixel1 /= "000")) then
						--LEDR(7) <= '1';
						SV <= end_p2;
					elsif(dir = p2down and (BottomPixel1 /= "000")) then
						--LEDR(6) <= '1';
						SV <= end_p2;
					elsif(dir = p2up and (TopPixel1 /= "000")) then  
						--LEDR(5) <= '1';
						SV <= end_p2;
					else 
						SV<= draw1;
					end if;
			
--					
					
				when end_p1 =>
--					if (lives = "0001") then
--						x <= "000000";
--						y <= "00000";
--						newgame <= true;
--						SV <= end2_p1;
					if (gesture = x"1C") then
						if (lives > 1) then
							lives <= lives - 1;
							newgame <= false;
							
						elsif(lives = 0) then
							mem_wr <= '0';	
							x <= "000000";	
							y <= "00000";
							SV <= clean0;			
							px <= to_unsigned(20, 6);	
							py <= to_unsigned(15,5);
							Player2x <= to_unsigned(40,6);
							Player2y <= to_unsigned(15,5);
							LeftPixel1 <= "000";
							RightPixel1 <= "000"; 
							TopPixel1 <= "000";
							BottomPixel1 <= "000";
							lives <= "0011";
							lives2 <= "0011";
							newgame <= true;
						end if;
						SV <= erase1;
					else
						SV <= end_p1;
					end if;		
				
				
			when end_p2 => 					
			if (lives2 = "0001") then
					x <= "000000";
					y <= "00000";
				   newgame <= true;
					SV <= end2_p2;
						
			elsif (gesture = x"1C") then
				if (lives2 > 1) then
					lives2 <= lives2 - 1;
					
				else
					mem_wr <= '0';	
					x <= "000000";	
					y <= "00000";
					--SV <= clean0;			
					px <= to_unsigned(20, 6);	
					py <= to_unsigned(15,5);
					Player2x <= to_unsigned(40,6);
					Player2y <= to_unsigned(15,5);
					LeftPixel1 <= "000";
					RightPixel1 <= "000"; 
					TopPixel1 <= "000";
					BottomPixel1 <= "000";
					lives <= "0011";
					lives2 <= "0011";
				end if;
				newgame <= false;
				SV <= erase1;
			end if;
				
			when end2_p1 =>
				mem_wr <= '1';
				if ( x > screen_width and y < screen_height) then
					x <= "000000";
					y <= y+1;
					SV <= end2_p1;
					mem_in <= pcolor;
				elsif (y = screen_height) then
					lives2 <= "0000";
					SV <= end_p2; 
				else
					x <= x+1;
					mem_in <= pcolor;
					SV <= end2_p1; 
				end if;
				
			when end2_p2=>
				mem_wr <= '1';
				if ( x > screen_width and y < screen_height ) then
					x <= "000000";
					y <= y+1;
					SV <= end2_p2;
					mem_in <= p2color;
				elsif (y = screen_height) then
					lives <= "0000";
					SV <= end_p1;
				else
					x <= x+1;
					mem_in <= p2color;
					SV <= end2_p2; 
				end if;	
            --------------------------------------------------
            when erase1 =>
					x<="000000";
					y<= "00000";
               SV <= erase2;
           
			  when erase2 =>
               SV <= clean0;
       
            when draw1 =>
               mem_wr <= '0';    
               SV <= draw2;   
           
			  when draw2 =>
               SV <= move0;
            --------------------------------------------------
            when others =>
               SV <= clean0;
         end case;
      end if;     
   end process;
end architecture DE1_SoC_MTL2;