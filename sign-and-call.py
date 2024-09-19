import subprocess
import json
import binascii

# Function to sign a message using fastcrypto
def sign_message(message, private_key):
    print(f"Signing message: {message}")
    
    # Strip quotes from private key
    private_key = private_key.strip('"')  # Remove any quotes that might have been loaded

    # Convert message to hex (assuming message needs to be in hex format)
    hex_message = binascii.hexlify(message.encode()).decode()
    print(f"Hex-encoded message: {hex_message}")
    
    # Command to sign the hex message with the private key
    sign_command = f"./target/debug/sigs-cli sign --scheme bls12381-minpk --msg {hex_message} --secret-key {private_key}"
    print(f"Sign command: {sign_command}")
    
    process = subprocess.Popen(sign_command.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, error = process.communicate()

    if error:
        print(f"Error during signing: {error.decode('utf-8')}")
        return None

    sign_output = output.decode("utf-8").splitlines()
    print(f"Sign output: {sign_output}")
    
    if "Error" in sign_output[0]:
        print(f"Error in signing: {sign_output[0]}")
        return None

    # Strip quotes from the signature
    signature = sign_output[0].split(": ")[1].strip('"')
    print(f"Signature generated: {signature}")

    return signature, hex_message


# Function to call the Sui contract using the Sui CLI
def call_contract(signature, hashed_message, amount, game_object_id, package_id):
    if not signature:
        print("No valid signature generated. Exiting.")
        return None
    
    print(f"Calling contract with signature: {signature}")
    print(f"Hashed message: {hashed_message}")
    print(f"Amount: {amount}")
    print(f"Game object ID: {game_object_id}")
    print(f"Package ID: {package_id}")

    transaction_command = [
        "sui",
        "client",
        "call",
        "--package", package_id,
        "--module", "nft",
        "--function", "claim_reward",
        "--args", game_object_id,
        f"{signature}", 
        f"{hashed_message}", 
        str(amount),
        "--gas-budget", "1000000",
    ]
    
    print(f"Transaction command: {' '.join(transaction_command)}")
    
    process = subprocess.Popen(transaction_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, error = process.communicate()

    if error:
        print(f"Error during contract call: {error.decode('utf-8')}")
        return None

    print(f"Contract call output: {output.decode('utf-8')}")
    return output.decode("utf-8")


# Main workflow
if __name__ == "__main__":
    print("Loading keypair from 'keypair.json'")
    # Load the keypair from JSON file
    with open("keypair.json", "r") as key_file:
        key_data = json.load(key_file)
        private_key = key_data["private_key"]
        print(f"Private key loaded: {private_key}")

    # Replace this with your actual message to be hashed (e.g., wallet address + claim amount)
    message = "hashed_message_to_sign"
    print(f"Message to be signed: {message}")

    # Step 1: Sign the hashed message and convert the message to hex
    signature, hex_message = sign_message(message, private_key)
    
    if signature:
        print(f"Signature: {signature}")
    else:
        print("Error in signature generation. Exiting.")
        exit(1)

    # Step 2: Call the contract
    game_object_id = "0x62d15743b2f191869d355e6e391476f6a564d3e76f50b2b11f3d290a584d7b9b"  # Replace with the actual Game object ID
    package_id = "0x0d3782976724e46246dcad7cc63c29a1f142fdabbddeaeb10e7c3dec168edeb3"      # Replace with the actual Package ID
    amount = 1000                   # Replace with the actual claim amount

    print(f"Calling contract with signature, hashed message, and game details.")
    result = call_contract(signature, hex_message, amount, game_object_id, package_id)
    
    if result:
        print(f"Contract Call Result: {result}")
    else:
        print("Error in contract call. Check above logs for more details.")
