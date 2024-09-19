import subprocess
import re
import shutil

def run_command(command):
    """Run a terminal command and return the output."""
    result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output = result.stdout.decode('utf-8') + result.stderr.decode('utf-8')
    return output

def clean_object_id(object_id):
    """Clean up ObjectID by removing invalid characters like pipes or spaces."""
    # Use regex to remove non-hexadecimal characters (like '│' or extra spaces)
    return re.sub(r'[^a-fA-F0-9x]', '', object_id)

def extract_object_ids(publish_response):
    """Extract the relevant object IDs from the publish response."""
    lines = publish_response.splitlines()
    package_id, game_id, treasury_id = None, None, None

    # Debugging: print the response to see the structure and line numbers
    print("Full publish response:")
    for idx, line in enumerate(lines):
        print(f"{idx}: {line}")

    # Adjusting based on the line numbers observed
    for i, line in enumerate(lines):
        if 'PackageID:' in line:
            package_id = clean_object_id(line.split('PackageID: ')[1].strip())
            print(f"Found PackageID: {package_id}")

        # Looking for ObjectType with ::nft::GameData
        if '::nft::GameData' in line:
            game_id = clean_object_id(lines[i-3].split('ObjectID: ')[1].strip())  # GameData ObjectID found 3 lines above
            print(f"Found GameData ObjectID: {game_id}")
        
        # Looking for ObjectType with ::coin::TreasuryCap
        if '::coin::TreasuryCap' in line:
            treasury_id = clean_object_id(lines[i-3].split('ObjectID: ')[1].strip())  # TreasuryCap ObjectID found 3 lines above
            print(f"Found TreasuryCap ObjectID: {treasury_id}")

    if not package_id:
        print("Failed to find PackageID in the response.")
    if not game_id:
        print("Failed to find GameData ObjectID in the response.")
    if not treasury_id:
        print("Failed to find TreasuryCap ObjectID in the response.")

    return package_id, game_id, treasury_id

def create_addresses_ts(package_id, game_id, treasury_id):
    """Create addresses.ts file with extracted information."""
    addresses_content = f"""
export const ADDRESSES = {{
  PACKAGE: "{package_id}",
  GAME: "{game_id}",
  CLOCK: "0x6",
  NFT_TYPE: "{package_id}::nft::City",
  TOKEN_TYPE: "{package_id}::sity::SITY",
}};
    """
    # Path to save the generated addresses.ts file
    addresses_ts_path = 'addresses.ts'
    with open(addresses_ts_path, 'w') as f:
        f.write(addresses_content)
    print(f"{addresses_ts_path} created successfully.")

    # Path to copy the addresses.ts file to the frontend directory
    destination_path = '/Users/yusufanilyazici/Documents/SuiCity/14september2024/frontend/addresses.ts'

    # Copying the file to the specified destination
    shutil.copyfile(addresses_ts_path, destination_path)
    print(f"{addresses_ts_path} copied to {destination_path}.")

def deploy_package():
    """Main function to deploy the package."""
    # Step 1: Run 'sui move build'
    print("Building the Move package...")
    build_output = run_command("sui move build")
    if "error" in build_output:
        print("Build failed. Check the output for errors.")
        return
    print("Build successful.")

    # Step 2: Run 'sui client publish'
    print("Publishing the package...")
    publish_output = run_command("sui client publish --skip-dependency-verification")
    if "Success" not in publish_output:
        print("Publish failed. Check the output for errors.")
        return
    print("Publish successful.")

    # Step 3: Extract the necessary object IDs
    package_id, game_id, treasury_id = extract_object_ids(publish_output)

    # Handle case where IDs could not be extracted
    if not all([package_id, game_id, treasury_id]):
        print("Failed to extract all necessary object IDs.")
        return

    # Step 4: Create addresses.ts file and copy it to the frontend directory
    create_addresses_ts(package_id, game_id, treasury_id)

    # Step 5: Run the final call
    print("Calling create_pool function...")
    final_call = f"sui client call --package {package_id} --module nft --function create_pool --args {game_id} {treasury_id} --gas-budget 5000000"
    final_output = run_command(final_call)

if __name__ == "__main__":
    deploy_package()
