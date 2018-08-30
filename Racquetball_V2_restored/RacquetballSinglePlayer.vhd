library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity RacquetballSinglePlayer is
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

architecture DE1_SoC_MTL2 of RacquetballSinglePlayer is
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
	signal game_over : boolean;
	
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
					collision_p1,collision_p2,
					update100,update200,update300,update400,update500,update600,
					update700,update800,update900, end_check, end_game, end_player1,draw_player1);
   

   signal SV : state;
      
   type direction is (nothing,p2down,p2left,p2right,p2up);
   signal dir: direction;

   type pdirection  is (nothing,pleft, pright, pdown, pup);
   signal pdir: pdirection;

   signal VGA_R, VGA_G, VGA_B : std_logic_vector(7 downto 0);
   alias  VGA_HS : std_logic is GPIO_1(30); --HSD
   alias  VGA_VS : std_logic is GPIO_1(31); --VSD
   alias  DCLK : std_logic is GPIO_1(1);  --pixel clock = 33.3MHz

   TYPE Touch_state IS (wait_for_ready, get_code, examine, examine2);
   SIGNAL TS : Touch_state;   
	
   signal gesture : std_logic_vector(7 downto 0);
   signal ready: std_logic;
   
   signal speed, old_speed: unsigned(3 downto 0);
   signal queue: std_logic_vector(1 downto 0);
   
   signal AI, old_AI : std_logic_vector(3 downto 0);
	
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
	
	
Touch_SensorGesture_Handler: process(CLOCK, reset)
   begin
      if(reset = '0') then 
         speed <= x"4";
			AI <= "0001";
			
			go <= false;		
			pdir <= nothing;	
			dir <= nothing;
			OP_num <= 0;		
			
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
					
					TS <= examine2;
				
				WHEN examine2 =>	
					
					
					if(gesture = x"10") then	--Move Up
						go <= true;
						OP_num <= 3;
						pdir <= pup;
						LEDR(5) <= '1';
				
					elsif(gesture = x"18") then	--Move Down
						go <= true;
						pdir <= pdown;
						OP_num <= 0;
						LEDR(4) <= '1';
						
					elsif(gesture = x"14") then	--Move Left
						go <= true;
						pdir <= pleft;
						OP_num <= 1;
						LEDR(3) <= '1';
						
					elsif(gesture = x"1C") then	--Move Right
						go <= true;
						pdir <= pright;
						OP_num <= 2;	
						LEDR(2) <= '1';
					
--					elsif(game_over = true) then
--						go <= false;
--						pdir <= nothing;
--						--game_over <= false;	
						
               end if;
					
               TS <= wait_for_ready;
               LEDR(5) <= '0';
					LEDR(4) <= '0';
					LEDR(3) <= '0';
					LEDR(2) <= '0';
            WHEN OTHERS =>
               TS <= wait_for_ready;
         END CASE;
      end if;     
   end process;
	
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
		
		
main: process(clock, reset)
      variable count : integer range 0 to 7;
		variable mode : integer;
      begin
      
      if(reset = '0') then       
         mem_wr <= '0';   
         x <= "000000";   --initialization Video RAM
         y <= "00000"; --address: x=0 and y=0
			px <= to_unsigned(20, 6); 
			py <= to_unsigned(15,5);	
         lives <= "0011";
			lives2 <= "0011";
			LeftPixel1 <= "000";
			RightPixel1 <= "000"; 
			TopPixel1 <= "000";
			BottomPixel1 <= "000";
			mode := 0;
			
			old_speed <= speed;
			old_AI <= AI;
			
			game_over <= false;
			SV <= clean0;
			
		elsif(clock'event and clock = '1') then
			case SV is
				when clean0 => --Shouldn't need to touch
					mem_wr <= '1';
					px <= to_unsigned(20, 6);	--Set p1x
					py <= to_unsigned(15,5); --Set p1y
					
				
               if(lives = "0011" and (y = 0 and (x = 7 or x = 9 or x = 11))) then --Draws 3 lives if present
                  mem_in <= lives_sprite; --Works
               elsif(lives = "0010" and (y = 0 and (x = 9 or x = 11))) then --Draws 2 lives if present
                  mem_in <= lives_sprite; --Works
               elsif(lives = "0001" and (y = 0 and x = 11)) then --Draws 1 life if present
                  mem_in <= lives_sprite; --Works
               elsif((x = 3 and (y >= 1 and y <= 29)) or (x = 46 and (y >= 1 and y <= 29)) or (y = 1 and (x >= 3 and x <= 46)) or (y = 29 and (x >= 3 and x <= 46))) then
                  mem_in <= border;    --Draws border
					else
                  mem_in <= background;   --Fill background
               end if;
               SV <= clean1;
            
				when clean1 => --Don't touch
               x <= x+1;
               SV <= clean2;
            
				when clean2 => --Don't touch
               mem_wr <= '0';    
               if(x > screen_width - 1) then 
                  x<= "000000";
                  y <= y+1;
                  SV <= clean3;
               else
                  SV <= clean0;
               end if;
               
            when clean3 => --Don't touch
               if(y > screen_height - 1) then 
                  SV <= move0;
               else
                  SV <= clean0;
               end if;
					
				when move0 => --Don't touch
					queue <= queue(0) & slow_clock;
					SV <= move1;
				when move1 => --Don't touch
					if (speed /= old_speed) then
						old_speed <= speed;
						SV <= ws0;
					elsif(AI /= old_AI) then
						old_AI <= AI;
						SV <= ws0;
					elsif(queue = "01") then
						SV <= update1;               --update speed button sprites    
					else
						SV <= move0;
					end if;
					
				when ws0 => 
               count := 0;
               old_x <= x;
               old_y <= y;
               SV <= ws1;
            
				when ws1 => --Drawing/Updating speed buttons and AI buttons
               case count is
                  when 0 => --Draw speed button 1 at (1,10)
                     X <= to_unsigned(1, 6);
                     Y <= to_unsigned(10, 5);
                     if(speed = x"8") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  when 1 => --Draw speed button 2  at (1,12)
                     X <= to_unsigned(1, 6);
                     Y <= to_unsigned(12, 5);
                     if(speed = x"4") then	
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  when 2 => --Draw speed button 3 at (1,14)
                     X <= to_unsigned(1, 6);
                     Y <= to_unsigned(14, 5);
                     if(speed = x"2") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  when 3 => --Draw speed button 4 at (1,16)
                     X <= to_unsigned(1, 6);
                     Y <= to_unsigned(16, 5);
                     if(speed = x"1") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
				
						when 4 => --Draws AI button 1 at (48,10)
                     X <= to_unsigned(48, 6);
                     Y <= to_unsigned(10, 5);
                     if(AI = "0011") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  
						when 5 => --Draws AI button 2 at (48,12)
                     X <= to_unsigned(48, 6);
                     Y <= to_unsigned(12, 5);
                     if(AI = "0010") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";				
                     end if;
                  
						when 6 => --Draws AI button 3 at (48,14)
                     X <= to_unsigned(48, 6);
                     Y <= to_unsigned(14, 5);
                     if(AI = "0001") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  
						when 7 => --Draws AI button 4 at (48,16)
                     X <= to_unsigned(48, 6);
                     Y <= to_unsigned(16, 5);
                     if(AI = "0000") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;	
                  when others =>				
                     null;
               end case;
               mem_wr <= '1'; 
               SV <= ws2;  
            
				when ws2 =>
               count := count + 1; --Increments count, draws next button
               SV <= ws3;
            when ws3 =>
               mem_wr <= '0'; 
               if(count <= 7) then --Restarts process if count has been fully incremented
                  SV <= ws1;
               else
                  X <= old_x; --Resets x and y position
                  Y <= old_y;
						if(mode = 1) then
							SV <= end_player1;
						elsif(mode = 2) then
							SV <= end_game;
						else
							SV <= move0; --Back to move0 check clock again
						end if;
               end if;
   
			when pdraw1 =>
				if(go) then
					x <= px;
					y <= py;
					mem_wr <= '1';		
					mem_in <= pcolor;
					SV <= pdraw2;
				else
					SV <= move0;
				end if;
				
--				when draw1 =>
--					mem_wr <= '0'; 
--					SV <= draw2;
--				when draw2 =>
--					SV <= move0;
--					
				when update1 =>	
						mem_wr <= '0';	
						x <= x - 1;
						SV <= update2;
				when update2 =>
						SV <= update3;
				when update3 => --Get coordinates of pixel to left of x and y
						LeftPixel1 <= unsigned(mem_out);	
						y <= y + 1;	
						x <= x + 1;	
						SV <= update4;
				when update4 =>	
						SV <= update5;
				when update5 => --Get coordinates of pixel below x and y
						BottomPixel1 <= unsigned(mem_out);		
						x <= x + 1;
						y <= y - 1;
						SV <= update6;		
				when update6 =>	
						SV <= update7;
				when update7 =>
						RightPixel1 <= unsigned(mem_out); --Get coordinates of pixel to right of x and y
						y <= y - 1;
					   x <= x - 1;	
						SV <= update8;	
				when update8 =>	
						SV <= update9;
				when update9 =>
						TopPixel1 <= unsigned(mem_out); --Get coordinates of pixel above x and y
						SV <= collision_p1; --Check for a collision
			
			when collision_p1 => --Checks for collisions 
				if( pdir = pleft and (LeftPixel1 /= "000")) then --Check left space for collision
					SV	<= end_check;
				elsif(pdir = pright and (RightPixel1 /= "000")) then --Check right space for collision
					SV <= end_check;
				elsif(pdir = pdown and (BottomPixel1 /= "000")) then --Check bottom space for collision
					SV <= end_check;
				elsif(pdir = pup and (TopPixel1 /= "000")) then --Check top space for collision
					SV <= end_check;
				elsif(pdir = nothing) then
					SV <= move0;
				else 
					--go <= true;
					SV<= pupdate; --Update px and py coordinates if no collision
				end if;
			
			when pupdate => --Done
				case pdir is 
					when nothing =>
						LEDR(8) <= '1';
					when pleft =>		
						if(go) then				
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
			SV <= pdraw1;
			
			
			when end_check =>
				if(lives >= 1) then
					lives <= lives - 1;
					SV <= end_player1;
				elsif(lives = 0) then
					SV <= end_game;
				end if;
           
			when end_player1 =>
				
				LEDR(1) <= '1';
				if(mode /= 1) then
					mode:= 1;
					SV <= move0;
				elsif(gesture = x"48") then
				
					x <= "000000";
					y <= "00000";
					LeftPixel1 <= "000";
					RightPixel1 <= "000"; 
					TopPixel1 <= "000";
					BottomPixel1 <= "000";
					--speed <= x"0"; --Random setting for speed
					--AI <= "0100"; --Random setting for AI button
					game_over <= false;
					--mode := 0;
					LEDR(1) <= '0';
					SV <= clean0;
				else
					SV <= end_player1;
				end if;
				
				
			when end_game =>	
				LEDR(0) <= '1';
				if(mode /= 2) then
					mode:= 2;
					SV <= move0;
				elsif(gesture = x"48") then
					
					x <= "000000";
					y <= "00000";
					
					LeftPixel1 <= "000";
					RightPixel1 <= "000"; 
					TopPixel1 <= "000";
					BottomPixel1 <= "000";
					
					lives <= "0000";
					
					--speed <= x"0"; --Random setting for speed
					--AI <= "0100"; --Random setting for AI button
					
					game_over <= true;
				  -- mode := 0;
					LEDR(0) <= '0';
					SV <= clean0;
				else
					SV <= end_game;
				end if;
			
			when others =>
               SV <= clean0;
         end case;
      end if;     
   end process;
end architecture DE1_SoC_MTL2;
				
				