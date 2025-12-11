import subprocess
import os
import time

# Get the current directory
current_directory = os.path.dirname(os.path.realpath(__file__))

# File paths for the Python files
file1_path = os.path.join(current_directory, 'restocks.py')
file2_path = os.path.join(current_directory, 'purchases.py')
file3_path = os.path.join(current_directory, 'competitor_prices.py')
file4_path = os.path.join(current_directory, 'web_clicks.py')
file5_path = os.path.join(current_directory, 'pg_seed.py')

# Start file1.py in a separate process
process1 = subprocess.Popen(['python3', file1_path])

# Start file2.py in a separate process
process2 = subprocess.Popen(['python3', file2_path])

# Start file3.py in a separate process
process3 = subprocess.Popen(['python3', file3_path])

# Start file4.py in a separate process
process4 = subprocess.Popen(['python3', file4_path])

# Start file5.py in a separate process
process5 = subprocess.Popen(['python3', file5_path])

# Wait for both processes to finish (which they never will in this case)
process1.wait()
process2.wait()
process3.wait()
process4.wait()
process5.wait()
