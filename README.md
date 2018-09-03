# TRON-FPGA-Project
This project was undertaken as a final project for an EDA course in my junior year of college. The goal of the project was to recreate the famous TRON game using a Cyclone V based Terasic development board which was equipped with a multi-touch touchscreen display. Below are some of the tasks that needed to be accomplished for this project:

- Draw the game background and setting
- Draw sprites for things such as player icon, AI icon, speed button, AI button, border, etc.
- Implement a system to recognize gestures on the touch screen and tie them to specific actions 
- Poll the touchscreen inputs at specific X,Y coordinates and check for matches at locations of known buttons (i.e. diffculty setting, speed, etc.)
- Implement a function to update the pace of the game (i.e. how fast the "lightbikes" move) and a button on the screen to allow the user to toggle different speeds at will
- Implement a function to change the AI's difficulty level based on user input corresponding to a button on the screen
- Map an onboard toggle switch to a global reset in order to easily reset the game without power-cycling
- Design multiple levels of AI for the computer player to implement more advanced design-making in order to make the game more difficult for the human player (see the AI_2 and AI_3 flow charts for more detail)
- Design and implement a main FSM to handle the drawing of the two players, drawing of the background and border, player movement, player collision detection, and reading of the various X,Y coordinates where the on-screen options buttons were drawn (speed, difficulty)




*The main project is called Racquetball V2 because we based the initial design off of a Pong like game and it was easier to keep building upon this instead of restarting from scratch*
