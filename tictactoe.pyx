#cython: language_level=3, boundscheck=False, wraparound=False, nonecheck=False

from libc.stdio cimport printf, scanf
from libc.string cimport memset, memcpy

ctypedef unsigned long long U64

DEF infinity = 10000
DEF win_combs = 49
DEF cells = 27

DEF hash_size = 0x400000
DEF no_hash_entry = 100000
DEF hashf_exact = 0
DEF hashf_alpha = 1
DEF hashf_beta = 2

cdef enum:
	player, opponent,
	win_score = 1000

cdef struct node:
	int move, score
	U64 nodes

cdef struct tt:

	U64 hash_key
	int depth, flag, score, best

cdef:
	int side, ply
	int[win_combs][3] win_table
	unsigned int random_state = 1804289383
	tt hash_table[hash_size]
	U64 marker_keys[2][cells]
	U64 hash_key, side_key 
	U64 bitboards[2]

# array of all possible wins
win_table = [
	# rows (per board)
	[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11], [12, 13, 14], [15, 16, 17], [18, 19, 20], [21, 22, 23], [24, 25, 26],
	# columns (per board)
	[0, 3, 6], [1, 4, 7], [2, 5, 8], [9, 12, 15], [10, 13, 16], [11, 14, 17], [18, 21, 24], [19, 22, 25], [20, 23, 26],
	# diagonals (per board)
	[0, 4, 8], [2, 4, 6], [9, 13, 17], [11, 13, 15], [18, 22, 26], [20, 22, 24],
	# stacks (between boards)
	[0, 9, 18], [1, 10, 19], [2, 11, 20], [3, 12, 21], [4, 13, 22], [5, 14, 23], [6, 15, 24], [7, 16, 25], [8, 17, 26],
	# diagonals (between board)
	[0, 12, 24], [1, 13, 25], [2, 14, 26], [6, 12, 18], [7, 13, 19], [8, 14, 20], [0, 10, 20], [3, 13, 23], [6, 16, 26],
	[2, 10, 18], [5, 13, 21], [8, 16, 24], [0, 13, 26], [2, 13, 24], [6, 13, 20], [8, 13, 18]
]

# function for placing markers
cdef inline U64 set_bit(U64 bitboard, char square):
	return bitboard | <U64> 1 << square

# function for checking if marker is at a square
cdef inline U64 get_bit(U64 bitboard, char square):
	return bitboard & <U64> 1 << square

# function for removing markers
cdef inline U64 pop_bit(U64 bitboard, char square):
	return bitboard & ~(<U64> 1 << square)

# used to create pseudo random numbers
cdef U64 get_random_U32_number():
	
	global random_state

	random_state ^= random_state << 13;
	random_state ^= random_state >> 17;
	random_state ^= random_state << 5;

	return random_state

# used to create larger pseudo random numbers
cdef U64 get_random_U64_number():

	cdef U64 n1, n2, n3, n4;

	n1 = <U64> (get_random_U32_number()) & 0xFFFF
	n2 = <U64> (get_random_U32_number()) & 0xFFFF
	n3 = <U64> (get_random_U32_number()) & 0xFFFF
	n4 = <U64> (get_random_U32_number()) & 0xFFFF

	return n1 | (n2 << 16) | (n3 << 32) | (n4 << 48)

# generates zobrist hash keys to uniquely identify positions in the transposition table
cdef void generate_hash_keys():

	global marker_keys, side_key
	cdef int i, j

	for i in range(2):
		for j in range(cells):
			marker_keys[i][j] = get_random_U64_number()

	side_key = get_random_U64_number()

# resets the hash table for new use
cdef void clear_hash_table():
	
	cdef int index
	for index in range(hash_size):

		hash_table[index].hash_key = 0
		hash_table[index].depth = 0
		hash_table[index].flag = 0
		hash_table[index].best = 0
		hash_table[index].score = 0

# searches the hash table to try to score a move
cdef int probe_hash_table(int depth, int alpha, int beta, int* best):

	cdef:
		int adjusted_score = no_hash_entry
		int score
		tt *hash_entry = &hash_table[hash_key % hash_size]

	# if entry exists in the transposition table and their move has searched as far as or farther than we will
	if hash_entry.hash_key == hash_key and hash_entry.depth >= depth:

		# we can order this move as first even if we don't get a score from the table
		best[0] = hash_entry.best

		# correct the score for our current ply
		score = hash_entry.score
		if score > win_score:
			score -= ply
		elif score < -win_score:
			score += ply
		
		# if we have an exact entry we can use the saved score
		if hash_entry.flag == hashf_exact:
			adjusted_score = score
		# if we have an alpha entry and the entry's score is less than our alpha's, our alpha is the best score
		elif hash_entry.flag == hashf_alpha and score <= alpha:
			adjusted_score = alpha
		# if we have a beta entry and the entry's score is greater than our beta's, we have a beta cutoff, so our beta is the best score
		elif hash_entry.flag == hashf_beta and score >= beta:
			adjusted_score = beta
	
	return adjusted_score

# stores the position, its score, and the best move in the position into the hash table
cdef void store_hash_entry(int score, int depth, int flag, int best):

	cdef tt *hash_entry = &hash_table[hash_key % hash_size]

	# correct the score for our current ply
	if score > win_score:
		score += ply
	elif score < -win_score:
		score -= ply

	hash_entry.hash_key = hash_key
	hash_entry.depth = depth
	hash_entry.flag = flag
	hash_entry.best = best
	hash_entry.score = score

# creates a node to return from the negamax function
cdef inline node create_node(int move, int score, U64 nodes):
	cdef node n
	n.move = move
	n.score = score
	n.nodes = nodes
	return n

# updates the board and global variables when a move is made
cdef inline void make_move(int move):
	global side, ply, hash_key, bitboards
	bitboards[side] = set_bit(bitboards[side], move)
	hash_key ^= marker_keys[side][move]
	hash_key ^= side_key
	side ^= 1
	ply += 1

# undoes the changes made in make_move()
cdef inline void take_back(int move):
	global side, ply, hash_key, bitboards
	side ^= 1
	ply -= 1
	hash_key ^= marker_keys[side][move]
	hash_key ^= side_key
	bitboards[side] = pop_bit(bitboards[side], move)

# checks if there is a draw (no more possible moves) are a player has won
cdef inline bint is_game_over():
	# if a player has won or there are no empty squares
	if check_win() or not ~(bitboards[0] | bitboards[1]):
		return True
	return False

# evaluation for the negamax function
cdef inline int evaluate():
	# evaluates wins that take fewer moves as better
	if check_win():
		return -win_score + ply
	return 0

# checks the win_table to see if a player has won the game
cdef inline bint check_win():
	
	cdef int i, j, counter
	# iterate over each win combination from the win_table
	for i in range(win_combs):

		# iterate over the 3 squares in the win_combination
		counter = 0
		for j in range(3):

			# check if the square is occupied
			if get_bit(bitboards[0], win_table[i][j]):
				counter += 1
			elif get_bit(bitboards[1], win_table[i][j]):
				counter += 4
		
		# if the counter is equal to 3 or 12, the player or opponent respectively has won.
		if counter == 3 or counter == 12:
			return True
	
	# if no one has won, return drawing
	return False

# recursive search function for finding the best move
cdef node negamax(int alpha, int beta, int depth):
	
	cdef:
		int move, score
		int tt_move = -1
		int hash_flag = hashf_alpha
		U64 occupied
		node best, value
	
	# return the evaluation when we reach the end of our search
	if not depth or is_game_over():
		return create_node(-1, evaluate(), 1)
	
	# if the position exists in the transposition table, return the best move, and the score
	score = probe_hash_table(depth, alpha, beta, &tt_move)
	if score != no_hash_entry and ply:
		return create_node(tt_move, score, 1)

	best = create_node(-1, -infinity, 0)
	occupied = bitboards[0] | bitboards[1]
	for move in range(cells):
		
		# if there is not a marker at the square
		if not get_bit(occupied, move):
			
			make_move(move)
			value = negamax(-beta, -alpha, depth - 1)
			value.score *= -1
			best.nodes += value.nodes
			take_back(move)

			# if the current score is better than the best so far, update the best move
			if value.score > best.score:
				best.move = move
				best.score = value.score

			# if we have a beta cutoff, return beta and the move that caused it
			if value.score >= beta:
				hash_flag = hashf_beta
				best.move = move
				break
			
			# if the score is better than alpha, set alpha to the score
			if value.score > alpha:
				hash_flag = hashf_exact
				alpha = best.score
	
	# saves the entry to the transposition table
	store_hash_entry(best.score, depth, hash_flag, best.move)

	return best

# base function for the minimax
cpdef int search_position(int depth, bint info):

	cdef:
		int cur_depth
		int alpha = -infinity
		int beta = infinity
		U64 total_nodes = 0
		node result
	
	# iterative deepening to attempt to reduce nodes by finding quicker wins
	for cur_depth in range(1, depth+1):
		
		result = negamax(alpha, beta, cur_depth)
		total_nodes += result.nodes
		if result.score:
			break
	
	# prints info about the search
	if info:
		printf("\nMove: %d", result.move)
		printf("\nScore: %d", result.score)
		printf("\nNodes: %lld\n", total_nodes)

	return result.move

# recursive function for searching the move tree, returns terminal nodes reached
cdef inline U64 perft_driver(int depth):

	if depth == 0 or check_win():
		return 1
	
	cdef:
		int move
		U64 occupied
		U64 nodes = 0

	occupied = bitboards[0] | bitboards[1]
	for move in range(cells):

		if not get_bit(occupied, move):

			make_move(move)
			nodes += perft_driver(depth - 1)
			take_back(move)
	
	return nodes

# base function for the perft
cpdef void perft(int depth):

	cdef:
		int move
		U64 nodes = 0
		U64 move_nodes, occupied
	
	printf("\nPerformance test:\n\n");
	
	occupied = bitboards[0] | bitboards[1]
	for move in range(cells):

		if not get_bit(occupied, move):

			make_move(move)
			move_nodes = perft_driver(depth - 1)
			take_back(move)
			nodes += move_nodes
			printf("    Move: %d | Nodes: %lld\n", move, move_nodes)
	
	printf("\nDepth: %d", depth)
	printf("\nNodes: %lld\n", nodes)

# resets the board variables
cdef void clear_board():
	global side, ply, bitboards
	side = 0
	ply = 0
	hash_key = 0
	memset(bitboards, 0, 16)

# converts the board from bitboards to real tic tac toe boards and prints it
cdef void print_board():

	cdef int i
	for i in range(cells):

		if get_bit(bitboards[0], i):
			printf("X")
		elif get_bit(bitboards[1], i):
			printf("O")
		else:
			printf(" ")

		if i % 9 == 8:
			printf("\n\n")
		elif i % 3 == 2:
			printf("\n-+-+-\n")
		else:
			printf("|")

# initialises the board and transposition table
def init():
	generate_hash_keys()
	clear_hash_table()
	clear_board()

# allows a person to play against the minimax algorithm
def play():

	cdef:
		int input_side, board, square, move, play_again_option
		bint play_again = True

	while play_again:

		printf("Which side do you want to play as (1-2): ")
		scanf("%d", &input_side)
		input_side -= 1

		if input_side < 0 or input_side > 1:
			printf("\nInvalid Input!\n")
			continue

		while True:

			if side == input_side:

				printf("\nEnter a board (1-3): ")
				scanf("%d", &board)
				board -= 1

				if board < 0 or board > 2:
					printf("\nInvalid Input!\n")
					continue
				
				printf("\nEnter a square (1-9): ")
				scanf("%d", &square)
				square -= 1

				if square < 0 or square > 8:
					printf("\nInvalid Input!\n")
					continue
				
				move = board * 9 + square
				make_move(move)
				print_board()
			
			else:

				move = search_position(8, False)
				printf("%d", move)
				printf("\nThe computer chose to go to board %d, square %d.\n", move // 9, move % 9 + 1)
				make_move(move)
				print_board()
			
			if check_win():

				if side == input_side:
					printf("\nThe computer won!\n")
				else:
					printf("\nYou won!\n")
				printf("Do you want to play again? (1 for yes, anything else for no): ")
				scanf("%d", &play_again_option)

				if play_again_option != 1:
					play_again = False
				break

		clear_hash_table()
		clear_board()