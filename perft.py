from timeit import timeit

setup = """
import tictactoe as ttt
ttt.init()
"""

time = timeit(stmt="ttt.perft(8)", setup=setup, number=1)
print(f"Time taken: {time:.4f}s")