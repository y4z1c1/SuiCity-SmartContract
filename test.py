import time
import subprocess
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
        with open('/Users/yusufanilyazici/Documents/SuiCity/31august2024/frontend/frontend/addresses.ts', 'r') as file:
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

def mint_nft():
    """Mint a new NFT."""
    package_id, game_id = parse_addresses_ts()

    if not package_id or not game_id:
        print("Error: Could not find necessary addresses in addresses.ts.")
        return None

    print("Minting new NFT...")
    mint_command = f"sui client call --package {package_id} --module nft --function build_city --args {game_id} 0x6 --gas-budget 20000000"
    mint_output = run_command(mint_command)

    print("Mint Output:")
    print(mint_output)

    # Extract NFT ID from the mint output
    nft_id_match = re.search(r'ObjectID: (0x[0-9a-fA-F]+)', mint_output)
    if nft_id_match:
        nft_id = nft_id_match.group(1)
        print(f"Minted NFT ID: {nft_id}")
        return nft_id
    else:
        print("Failed to mint NFT.")
        return None

def claim_sity(nft_id):
    """Claim SITY from the minted NFT."""
    package_id, game_id = parse_addresses_ts()

    if not package_id or not game_id:
        print("Error: Could not find necessary addresses in addresses.ts.")
        return

    print(f"Claiming SITY for NFT {nft_id}...")
    claim_command = f"sui client call --package {package_id} --module nft --function claim_sity --args {nft_id} {game_id} 0x6 --gas-budget 5000000"
    claim_output = run_command(claim_command)

    print("Claim SITY Output:")
    print(claim_output)

def accumulate_sity(nft_id):
    """Call accumulate_sity explicitly if needed."""
    package_id, game_id = parse_addresses_ts()

    if not package_id or not game_id:
        print("Error: Could not find necessary addresses in addresses.ts.")
        return

    print(f"Accumulating SITY for NFT {nft_id}...")
    accumulate_command = f"sui client call --package {package_id} --module nft --function accumulate_sity --args {nft_id} {game_id} 0x6 --gas-budget 5000000"
    accumulate_output = run_command(accumulate_command)

    print("Accumulate SITY Output:")
    print(accumulate_output)

def check_sity_accumulation(nft_id):
    """Mint an NFT, claim SITY, wait, accumulate, wait, and claim SITY again to check accumulation."""
    print("Step 1: Minting NFT...")
    nft_id = mint_nft()

    if not nft_id:
        print("Failed to mint NFT.")
        return

    print("Step 2: Claiming initial SITY...")
    claim_sity(nft_id)

    print("Waiting for accumulation period (20 seconds)...")
    time.sleep(20)  # Simulate waiting period (replace with actual wait time as necessary)

    print("Step 3: Accumulating SITY...")
    accumulate_sity(nft_id)

    print("Waiting for another accumulation period (20 seconds)...")
    time.sleep(20)

    print("Step 4: Claiming SITY again after waiting...")
    claim_sity(nft_id)

if __name__ == "__main__":
    check_sity_accumulation(None)
