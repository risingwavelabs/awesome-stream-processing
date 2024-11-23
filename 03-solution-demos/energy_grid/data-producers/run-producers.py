import subprocess
import os
import time

# Get the current directory
current_directory = os.path.dirname(os.path.realpath(__file__))

# File paths for the Python files
file1_path = os.path.join(current_directory, 'energy-consumed.py')
file2_path = os.path.join(current_directory, 'energy-produced.py')

# Start file1.py in a separate process
process1 = subprocess.Popen(['python3', file1_path])

# Start file2.py in a separate process
process2 = subprocess.Popen(['python3', file2_path])

# Wait for both processes to finish (which they never will in this case)
process1.wait()
process2.wait()