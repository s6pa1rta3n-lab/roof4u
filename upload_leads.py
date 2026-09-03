import csv
import sys
from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build

SCOPES = ['https://www.googleapis.com/auth/spreadsheets']
SERVICE_ACCOUNT_FILE = '/Users/solveetcoagula/Downloads/odin-500008-8336f284eedc.json'
SPREADSHEET_ID = '1YyhKGt_Z2yf9TfbH0cHCo_K4rwinTBh6p2oAxJY9W6I'

def main():
    creds = Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE, scopes=SCOPES)
    service = build('sheets', 'v4', credentials=creds)

    with open('validated_leads.csv', 'r') as f:
        reader = csv.reader(f)
        data = list(reader)

    body = {
        'values': data
    }
    
    service.spreadsheets().values().update(
        spreadsheetId=SPREADSHEET_ID, range='Sheet1!A1',
        valueInputOption='USER_ENTERED', body=body).execute()

    print(f"Successfully uploaded {len(data)-1} leads to Spreadsheet ID: {SPREADSHEET_ID}")

if __name__ == '__main__':
    main()
