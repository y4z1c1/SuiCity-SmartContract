import subprocess
import json
import re

def run_command(command):
    """Run a terminal command and return the output."""
    result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output = result.stdout.decode('utf-8') + result.stderr.decode('utf-8')
    return output

def parse_addresses_ts():
    """Parse the addresses.ts file to get the PACKAGE and GAME addresses."""
    addresses = {}
    try:
        with open('/Users/yusufanilyazici/Documents/SuiCity/14september2024/SuiCity/addresses.ts', 'r') as file:
            content = file.read()
            # Use regex to extract PACKAGE and GAME addresses
            addresses['PACKAGE'] = re.search(r'PACKAGE: "(.*?)"', content).group(1)
            addresses['GAME'] = re.search(r'GAME: "(.*?)"', content).group(1)
    except FileNotFoundError:
        print("Error: addresses.ts file not found.")
        return None, None
    except AttributeError:
        print("Error: Could not find PACKAGE or GAME in addresses.ts.")
        return None, None

    return addresses['PACKAGE'], addresses['GAME']

def withdraw_funds():
    """Withdraw funds from the GameData contract."""
    # Step 1: Parse addresses.ts to get the PACKAGE and GAME addresses
    package_id, game_id = parse_addresses_ts()
    
    if not package_id or not game_id:
        print("Error: Could not find necessary addresses in addresses.ts.")
        return
    
    # Step 2: Run the withdraw_funds function from the contract
    print("Calling withdraw_funds function...")
    withdraw_command = f"sui client call --package {package_id} --module nft --function withdraw_funds --args {game_id} --gas-budget 5000000"
    
    # Step 3: Execute the command
    withdraw_output = run_command(withdraw_command)
    
    print("Withdraw Output:")
    print(withdraw_output)

if __name__ == "__main__":
    withdraw_funds()
