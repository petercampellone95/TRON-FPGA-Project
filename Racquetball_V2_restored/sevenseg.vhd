library IEEE;
use IEEE.std_logic_1164.all;

entity sevenseg is
	port( ain  : in  std_logic_vector(3 downto 0);
			aout : out std_logic_vector(6 downto 0)
		);
end sevenseg;

architecture modified of sevenseg is 
begin
		   --gfedcba
  aout <= "1000000" when ain="0000" else --0
          "0000111" when ain="0001" else --1 --> t
          "0001100" when ain="0010" else --2 --> P
          "0010000" when ain="0011" else --3 --> g
          "0110111" when ain="0100" else --4 --> =
          "0010010" when ain="0101" else --5 
          "0101111" when ain="0110" else --6 --> r
          "1111000" when ain="0111" else --7
          "0000000" when ain="1000" else --8
          "0011000" when ain="1001" else --9
          "0001000" when ain="1010" else --A
          "0000011" when ain="1011" else --B
          "1000111" when ain="1100" else --C --> L
          "0100001" when ain="1101" else --D
          "0000110" when ain="1110" else --E
          "1111111" when ain="1111" else --F --> blank
          "1111111"; -- default

end architecture modified;
