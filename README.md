# 3d-TicTacToe
A minimax algorithm to attempt to find the best move in 3x3x3 tictactoe.

I've used a basic minimax algorithm with alpha beta pruning and a transposition table to search the tictactoe board's move tree to find the best moves.



Stats on my Intel Core i7-7700HQ CPU @ 2.80GHz:
* Perft test: 40-45 million nodes / second.
* Minimax search: ~2 million nodes / second.



# How to use:
Step 1 - Run the compile.bat file to compile the tictactoe.pyx file (requires a c compiler as it is written in cython).

Step 2 - Run either main.py to play against the computer or perft.py to see perft information.


# To Do:
* Add null move pruning
* Add late move reduction
* Account for symmetry of different position in the transposition table
* Add option for 4x4x4 tictactoe (3x3x3 is winning for the player who starts first)
* Add option to play against another person, not just the computer
* Add a graphical interface for playing against the computer
