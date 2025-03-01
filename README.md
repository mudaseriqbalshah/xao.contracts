# NFT Ticketing Smart Contract System

A Solidity-based NFT ticketing system with separate Parent Event and Artist contracts, focusing on validation rather than NFT attribute storage.

## Features

### Parent Event Contract
- NFT ticketing & pricing controls
- Escrowed payments & revenue splits
- Artist agreements, cancellations, and penalties
- Legal compliance & document attachments

### Artist Contract
- Individual agreement terms & guarantees
- Revenue share adjustments
- Performance obligations & set times
- Deposit management

### XAO Referral System
- AI-powered referral verification
- Engagement-based rewards
- DAO approval workflow
- Double-claim prevention

## AI Verification Flow

The referral system uses OpenAI's GPT-4o model to verify referrals by analyzing:
1. User activity patterns
2. Interaction timing
3. Behavioral signals

### Verification Process
1. User registers with referral data
2. AI service analyzes patterns for legitimacy
3. DAO reviews and approves verified referrals
4. Rewards distributed upon approval

### Integration Components
- Smart Contract: `XAOReferral.sol`
- AI Service: `referral_verification.py`
- OpenAI Integration: GPT-4o model

## Tech Stack
- Solidity ^0.8.19
- Truffle Framework
- OpenZeppelin Contracts
- Web3.js
- Python (OpenAI Integration)

## Prerequisites
- Node.js >= 16.0.0
- Truffle Suite
- Ganache CLI (for local development)
- Python 3.11
- OpenAI API Key

## Installation

1. Clone the repository
```bash
git clone <your-repo-url>
cd nft-ticketing-system
```

2. Install dependencies
```bash
npm install
```

3. Set up environment variables
```bash
OPENAI_API_KEY=your_api_key_here
```

4. Start local blockchain
```bash
npx ganache-cli
```

5. Compile contracts
```bash
npx truffle compile
```

6. Run migrations
```bash
npx truffle migrate
```

7. Run tests
```bash
npx truffle test
```

## Project Structure
```
├── contracts/           # Smart contracts
│   ├── interfaces/     # Contract interfaces
│   ├── ParentEvent.sol # Main event contract
│   ├── Artist.sol      # Artist contract
│   └── XAOReferral.sol # Referral contract
├── migrations/         # Deployment scripts
├── services/          # Backend services
│   └── referral_verification.py  # AI verification service
├── test/              # Test files
└── scripts/           # Utility scripts
```

## Testing
The project includes comprehensive tests covering:
- Event setup and validation
- Ticket minting and revenue tracking
- Artist contract linking
- Referral verification and rewards
- AI integration testing

### Referral Verification Format
```json
{
    "verified": true,
    "confidence": 0.95,
    "reasoning": "Natural activity patterns detected",
    "timestamp": "1708444800",
    "model_version": "gpt-4o"
}
```

## Future Features
- Dynamic pricing implementation
- Advanced cancellation system
- Automated revenue splits
- Enhanced AI verification metrics

## License
MIT

## Contributing
Contributions are welcome! Please feel free to submit a Pull Request.